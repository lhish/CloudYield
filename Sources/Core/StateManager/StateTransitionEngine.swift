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

    // 定时刷新网易云状态的计时器
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 0.1  // 每0.1秒刷新一次

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

        // 启动定时刷新网易云状态
        startRefreshTimer()

        // 初始化状态
        updateState()
    }

    /// 停止状态引擎
    func stop() {
        logInfo("停止状态引擎", module: "StateEngine")
        stopRefreshTimer()
    }

    /// 音频监控状态变化回调
    func onAudioStatusChanged(status: AudioMonitorStatus) {
        let oldStatus = lastAudioStatus
        lastAudioStatus = status

        logDebug("音频状态变化: isOtherAppAudible \(oldStatus.isOtherAppAudible) → \(status.isOtherAppAudible)", module: "StateEngine")

        // 更新状态
        updateState()
    }

    /// 获取当前状态
    func getCurrentState() -> AppState {
        return currentState
    }

    // MARK: - Private Methods - Timer

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.updateState()
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Private Methods - State Machine

    /// 更新状态（核心状态机逻辑）
    private func updateState() {
        // 获取网易云播放状态（通过 AppleScript）
        let isNeteasePlaying = musicController.isPlaying()

        // 计算新状态
        let newState = AppState.from(
            isOtherAppAudible: lastAudioStatus.isOtherAppAudible,
            isNeteasePlaying: isNeteasePlaying
        )

        // 检查状态是否变化
        if newState == currentState {
            return
        }

        let oldState = currentState
        currentState = newState

        logInfo("状态变化: \(oldState) → \(newState)", module: "StateEngine")

        // 处理状态转换
        handleStateTransition(from: oldState, to: newState)

        // 触发回调
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChanged?(self.currentState)
        }
    }

    /// 处理状态转换
    private func handleStateTransition(from oldState: AppState, to newState: AppState) {
        switch (oldState, newState) {
        // 进入冲突状态：其他应用出声 + 网易云也在播放
        // 立即暂停网易云
        case (_, .otherPlayingNeteasePlaying):
            logInfo("检测到冲突状态，立即暂停网易云...", module: "StateEngine")
            executePause()

        // 从“其他应用出声 + 网易云暂停”转到“其他应用静音 + 网易云暂停”
        // 如果是软件暂停的，立即恢复
        case (.otherPlayingNeteasePaused, .neteasePaused):
            if wasPausedByApp {
                logInfo("其他应用停止，立即恢复网易云...", module: "StateEngine")
                executeResume()
            }

        // 网易云被用户手动暂停（非冲突状态下从播放变为暂停）
        case (.neteasePlaying, .neteasePaused):
            // 用户手动暂停，清除软件暂停标记
            wasPausedByApp = false
            logDebug("用户手动暂停网易云", module: "StateEngine")

        // 网易云被用户手动恢复（非冲突状态下从暂停变为播放）
        case (.neteasePaused, .neteasePlaying):
            // 用户手动恢复，清除软件暂停标记
            wasPausedByApp = false
            logDebug("用户手动恢复网易云", module: "StateEngine")

        default:
            break
        }
    }

    /// 执行暂停操作
    private func executePause() {
        // 再次检查网易云是否在播放
        guard musicController.isPlaying() else {
            logInfo("网易云已不在播放，跳过暂停", module: "StateEngine")
            return
        }

        musicController.pause()
        wasPausedByApp = true

        // 更新状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateState()
        }
    }

    /// 执行恢复操作
    private func executeResume() {
        // 检查是否应该恢复
        guard wasPausedByApp else {
            logInfo("非软件暂停，跳过恢复", module: "StateEngine")
            return
        }

        // 检查其他应用是否仍在播放
        guard !lastAudioStatus.isOtherAppAudible else {
            logInfo("其他应用仍在播放，跳过恢复", module: "StateEngine")
            return
        }

        musicController.play()
        wasPausedByApp = false

        // 更新状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateState()
        }
    }
}
