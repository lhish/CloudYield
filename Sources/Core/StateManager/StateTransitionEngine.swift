//
//  StateTransitionEngine.swift
//  StillMusicWhenBack
//
//  状态转换引擎 - 基于6状态模型协调音频检测和音乐控制
//
//  6状态模型：
//  S1: NowPlaying=网易云播放中
//  S2: NowPlaying=网易云暂停
//  S3: 其他应用播放 + 网易云播放（冲突，需自动暂停）
//  S4: 其他应用播放 + 网易云暂停
//  S5: 其他应用空闲 + 网易云播放
//  S6: 其他应用空闲 + 网易云暂停
//

import Foundation

class StateTransitionEngine {
    // MARK: - Properties

    private var currentState: AppState = .s6_otherIdleNeteasePaused
    private let musicController: NeteaseMusicController
    private let mediaMonitor: MediaMonitorProtocol

    // 记录是否是软件暂停的网易云（用于自动恢复）
    private var wasPausedByApp = false

    // 缓存 NowPlaying 状态
    private var lastNowPlayingStatus = NowPlayingStatus.idle

    // 计时器（延迟执行暂停/恢复操作）
    private var pauseTimer: DelayTimer?
    private var resumeTimer: DelayTimer?

    // 定时刷新网易云状态的计时器
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 2.0  // 每2秒刷新一次

    // 状态变化回调
    var onStateChanged: ((AppState) -> Void)?

    // MARK: - Initialization

    init(musicController: NeteaseMusicController, mediaMonitor: MediaMonitorProtocol) {
        self.musicController = musicController
        self.mediaMonitor = mediaMonitor

        // 初始化计时器（3秒延迟）
        pauseTimer = DelayTimer(delay: 3.0)
        resumeTimer = DelayTimer(delay: 3.0)

        // 设置计时器回调
        pauseTimer?.onTimerExpired = { [weak self] in
            self?.executePause()
        }

        resumeTimer?.onTimerExpired = { [weak self] in
            self?.executeResume()
        }
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
        pauseTimer?.stop()
        resumeTimer?.stop()
        stopRefreshTimer()
    }

    /// NowPlaying 状态变化回调
    func onNowPlayingChanged(status: NowPlayingStatus) {
        let oldStatus = lastNowPlayingStatus
        lastNowPlayingStatus = status

        logDebug("NowPlaying 状态变化: isNeteaseAsNowPlaying \(oldStatus.isNeteaseAsNowPlaying) → \(status.isNeteaseAsNowPlaying), isOtherAppPlaying \(oldStatus.isOtherAppPlaying) → \(status.isOtherAppPlaying)", module: "StateEngine")

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
            isOtherAppPlaying: lastNowPlayingStatus.isOtherAppPlaying,
            isNeteasePlaying: isNeteasePlaying,
            isNeteaseAsNowPlaying: lastNowPlayingStatus.isNeteaseAsNowPlaying
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
        // 取消之前的计时器
        pauseTimer?.stop()
        resumeTimer?.stop()

        switch (oldState, newState) {
        // 进入 S3（冲突状态）：其他应用播放 + 网易云也在播放
        // 需要启动暂停计时器
        case (_, .s3_otherPlayingNeteasePlaying):
            logInfo("检测到冲突状态，启动暂停计时器...", module: "StateEngine")
            pauseTimer?.start()

        // 从 S4 转到 S6：其他应用停止播放，网易云仍暂停
        // 如果是软件暂停的，需要启动恢复计时器
        case (.s4_otherPlayingNeteasePaused, .s6_otherIdleNeteasePaused):
            if wasPausedByApp {
                logInfo("其他应用停止，启动恢复计时器...", module: "StateEngine")
                resumeTimer?.start()
            }

        // 从 S4 转到 S2：其他应用停止，NowPlaying 切回网易云但暂停
        // 如果是软件暂停的，需要启动恢复计时器
        case (.s4_otherPlayingNeteasePaused, .s2_neteasePausedAsNowPlaying):
            if wasPausedByApp {
                logInfo("NowPlaying 切回网易云，启动恢复计时器...", module: "StateEngine")
                resumeTimer?.start()
            }

        // 网易云被用户手动暂停（非冲突状态下从播放变为暂停）
        case (.s5_otherIdleNeteasePlaying, .s6_otherIdleNeteasePaused),
             (.s1_neteasePlayingAsNowPlaying, .s2_neteasePausedAsNowPlaying):
            // 用户手动暂停，清除软件暂停标记
            wasPausedByApp = false
            logDebug("用户手动暂停网易云", module: "StateEngine")

        // 网易云被用户手动恢复（非冲突状态下从暂停变为播放）
        case (.s6_otherIdleNeteasePaused, .s5_otherIdleNeteasePlaying),
             (.s2_neteasePausedAsNowPlaying, .s1_neteasePlayingAsNowPlaying):
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
            updateState()
            return
        }

        logInfo("执行暂停网易云...", module: "StateEngine")
        musicController.pause()
        wasPausedByApp = true

        // 更新状态
        updateState()
    }

    /// 执行恢复操作
    private func executeResume() {
        // 检查是否应该恢复
        guard wasPausedByApp else {
            logInfo("非软件暂停，跳过恢复", module: "StateEngine")
            return
        }

        // 检查其他应用是否仍在播放
        guard !lastNowPlayingStatus.isOtherAppPlaying else {
            logInfo("其他应用仍在播放，跳过恢复", module: "StateEngine")
            return
        }

        logInfo("执行恢复网易云...", module: "StateEngine")
        musicController.play()
        wasPausedByApp = false

        // 更新状态
        updateState()
    }
}
