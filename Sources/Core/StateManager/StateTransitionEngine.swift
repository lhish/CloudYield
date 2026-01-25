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
        refreshNeteasePlaying()

        guard lastKnownNeteasePlaying else {
            wasPausedByApp = false
            return
        }

        logInfo("检测到其他应用出声且网易云在播放，尝试暂停...", module: "StateEngine")
        if musicController.pause() {
            wasPausedByApp = true
            lastKnownNeteasePlaying = false
            return
        }

        // 暂停失败：稍后再刷新一次状态（避免立即刷屏/重试过猛）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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

        // 避免用户已手动恢复时重复点击“播放”导致脚本失败刷日志
        if musicController.isPlaying() {
            wasPausedByApp = false
            lastKnownNeteasePlaying = true
            return
        }

        logInfo("其他应用停止，尝试恢复网易云...", module: "StateEngine")
        if musicController.play() {
            wasPausedByApp = false
            lastKnownNeteasePlaying = true
            return
        }

        // 恢复失败：稍后再刷新一次状态（不强行重试，留给用户/下一次事件）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshNeteasePlaying()
            self?.publishStateIfNeeded()
        }
    }
}
