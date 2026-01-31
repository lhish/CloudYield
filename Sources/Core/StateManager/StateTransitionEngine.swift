//
//  StateTransitionEngine.swift
//  StillMusicWhenBack
//
//  状态转换引擎 - 基于音频检测 + 网易云控制
//
//  状态模型：
//  - otherPlayingNeteasePlaying: 其他应用出声 + 网易云播放（冲突，需自动暂停）
//  - otherPlayingNeteasePaused: 其他应用出声 + 网易云暂停
//  - neteasePlaying: 其他应用静音/停止出声 + 网易云播放
//  - neteasePaused: 其他应用静音/停止出声 + 网易云暂停
//

import Foundation

class StateTransitionEngine {
    // MARK: - Properties

    private var currentState: AppState = .neteasePaused
    private let musicController: NeteaseMusicController
    private let mediaMonitor: MediaMonitorProtocol

    // 记录是否是软件暂停的网易云（用于自动恢复）
    private var wasPausedByApp = false

    // 缓存音频监控状态
    private var lastAudioStatus = AudioMonitorStatus.idle

    // 缓存网易云播放状态（只在必要时刷新，避免高频 AppleScript 轮询）
    private var lastKnownNeteasePlaying = false

    // 静音后延迟恢复（避免短暂停顿/切歌导致频繁恢复）
    private let resumeAfterSilenceDelay: TimeInterval = 2.0
    private let resumeRetryBaseDelay: TimeInterval = 0.6
    private let resumeMaxRetryCount = 3
    private var resumeRetryCount = 0
    private var resumeWorkItem: DispatchWorkItem?

    // 状态变化回调
    var onStateChanged: ((AppState) -> Void)?

    // MARK: - Initialization

    init(musicController: NeteaseMusicController, mediaMonitor: MediaMonitorProtocol) {
        self.musicController = musicController
        self.mediaMonitor = mediaMonitor
    }

    // MARK: - Public Methods

    /// 启动状态引擎
    func start() {
        logInfo("启动状态引擎", module: "StateEngine")
        refreshNeteasePlaying()
        publishStateIfNeeded()
    }

    /// 停止状态引擎
    func stop() {
        logInfo("停止状态引擎", module: "StateEngine")
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
    }

    /// 音频监控状态变化回调
    func onAudioStatusChanged(status: AudioMonitorStatus) {
        let oldStatus = lastAudioStatus
        lastAudioStatus = status

        logDebug("音频状态变化: isOtherAppAudible \(oldStatus.isOtherAppAudible) → \(status.isOtherAppAudible)", module: "StateEngine")

        guard oldStatus.isOtherAppAudible != status.isOtherAppAudible else {
            return
        }

        if status.isOtherAppAudible {
            handleOtherAudioStarted()
        } else {
            handleOtherAudioStopped()
        }

        publishStateIfNeeded()
    }

    /// 获取当前状态
    func getCurrentState() -> AppState {
        return currentState
    }

    // MARK: - Private Methods - State Machine

    private func publishStateIfNeeded() {
        let newState = AppState.from(
            isOtherAppAudible: lastAudioStatus.isOtherAppAudible,
            isNeteasePlaying: lastKnownNeteasePlaying
        )
        guard newState != currentState else { return }

        let oldState = currentState
        currentState = newState

        logInfo("状态变化: \(oldState) → \(newState)", module: "StateEngine")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChanged?(self.currentState)
        }
    }

    private func refreshNeteasePlaying() {
        lastKnownNeteasePlaying = musicController.isPlaying()
    }

    private func handleOtherAudioStarted() {
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        resumeRetryCount = 0

        guard musicController.isRunning() else {
            wasPausedByApp = false
            lastKnownNeteasePlaying = false
            return
        }

        if musicController.pause() {
            wasPausedByApp = true
            lastKnownNeteasePlaying = false
            return
        }

        // 未能暂停：说明当前本来就没在播放（或暂停失败）。
        // 无论哪种情况，都不应在“其他应用静音后”自动恢复播放。
        wasPausedByApp = false

        // 未暂停（可能本来就没在播，也可能脚本失败）：稍后刷新一次状态，避免阻塞主线程
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshNeteasePlaying()
            self?.publishStateIfNeeded()
        }
    }

    private func handleOtherAudioStopped() {
        guard wasPausedByApp else {
            return
        }

        guard !lastAudioStatus.isOtherAppAudible else {
            return
        }

        scheduleResumeAfterSilence()
    }

    private func scheduleResumeAfterSilence() {
        resumeRetryCount = 0
        scheduleResumeAttempt(after: resumeAfterSilenceDelay, isFirstAttempt: true)
    }

    private func scheduleResumeRetry() {
        guard wasPausedByApp else { return }
        guard !lastAudioStatus.isOtherAppAudible else { return }

        guard resumeRetryCount < resumeMaxRetryCount else {
            logWarning("恢复失败已达上限，停止自动重试", module: "StateEngine")
            wasPausedByApp = false
            return
        }

        resumeRetryCount += 1
        let delay = resumeRetryBaseDelay * pow(1.6, Double(resumeRetryCount - 1))
        logWarning("恢复失败，\(String(format: "%.1f", delay)) 秒后重试 (\(resumeRetryCount)/\(resumeMaxRetryCount))", module: "StateEngine")
        scheduleResumeAttempt(after: delay, isFirstAttempt: false)
    }

    private func scheduleResumeAttempt(after delay: TimeInterval, isFirstAttempt: Bool) {
        resumeWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.attemptResume(isFirstAttempt: isFirstAttempt)
        }

        resumeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func attemptResume(isFirstAttempt: Bool) {
        guard wasPausedByApp else { return }
        guard !lastAudioStatus.isOtherAppAudible else { return }

        guard musicController.isRunning() else {
            wasPausedByApp = false
            lastKnownNeteasePlaying = false
            publishStateIfNeeded()
            return
        }

        if isFirstAttempt {
            logInfo("已静音 \(Int(resumeAfterSilenceDelay)) 秒，尝试恢复网易云...", module: "StateEngine")
        } else {
            logInfo("尝试恢复网易云（重试 \(resumeRetryCount)/\(resumeMaxRetryCount)）...", module: "StateEngine")
        }

        if musicController.play() {
            wasPausedByApp = false
            lastKnownNeteasePlaying = true
            publishStateIfNeeded()
            return
        }

        // 恢复失败：先刷新一次状态；如果仍未恢复且未达到上限，再做有限重试。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard self.wasPausedByApp else { return }
            guard !self.lastAudioStatus.isOtherAppAudible else { return }

            guard self.musicController.isRunning() else {
                self.wasPausedByApp = false
                self.lastKnownNeteasePlaying = false
                self.publishStateIfNeeded()
                return
            }

            self.refreshNeteasePlaying()
            self.publishStateIfNeeded()

            if self.lastKnownNeteasePlaying {
                self.wasPausedByApp = false
                return
            }

            self.scheduleResumeRetry()
        }
    }
}
