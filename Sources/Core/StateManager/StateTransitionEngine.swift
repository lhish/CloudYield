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
    private var isOtherAppPlaying = false

    // 计时器（延迟执行暂停/恢复操作）
    private var pauseTimer: DelayTimer?
    private var resumeTimer: DelayTimer?

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
        // 初始化状态
        updateState()
    }

    /// 停止状态引擎
    func stop() {
        logInfo("停止状态引擎", module: "StateEngine")
        pauseTimer?.stop()
        resumeTimer?.stop()
    }

    /// NowPlaying 状态变化回调
    func onNowPlayingChanged(status: NowPlayingStatus) {
        let oldIsOtherAppPlaying = isOtherAppPlaying
        isOtherAppPlaying = status.isOtherAppPlaying

        logDebug("NowPlaying 状态变化: isOtherAppPlaying \(oldIsOtherAppPlaying) → \(isOtherAppPlaying)", module: "StateEngine")

        // 更新状态
        updateState()
    }

    /// 获取当前状态
    func getCurrentState() -> AppState {
        return currentState
    }

    // MARK: - Private Methods

    /// 更新状态（核心状态机逻辑）
    private func updateState() {
        // 获取网易云播放状态（通过 AppleScript）
        let isNeteasePlaying = musicController.isPlaying()

        // 计算新状态
        // 注意：这里简化处理，不区分 S1/S2（NowPlaying是网易云）和 S5/S6（NowPlaying为空或其他应用暂停）
        // 因为从用户角度看，这些状态的行为是一样的
        let newState = AppState.from(
            isOtherAppPlaying: isOtherAppPlaying,
            isNeteasePlaying: isNeteasePlaying,
            isNeteaseAsNowPlaying: !isOtherAppPlaying && isNeteasePlaying  // 简化：如果没有其他应用播放且网易云在播放，视为网易云是 NowPlaying
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

        // 从 S3 转到 S5：其他应用停止播放，但网易云还在播放
        // 说明用户可能手动恢复了网易云，清除软件暂停标记
        case (.s3_otherPlayingNeteasePlaying, .s5_otherIdleNeteasePlaying):
            wasPausedByApp = false

        // 网易云被用户手动暂停（从播放状态变为暂停）
        case (.s5_otherIdleNeteasePlaying, .s6_otherIdleNeteasePaused),
             (.s1_neteasePlayingAsNowPlaying, .s2_neteasePausedAsNowPlaying):
            // 用户手动暂停，清除软件暂停标记
            wasPausedByApp = false

        // 网易云被用户手动恢复（从暂停状态变为播放）
        case (.s6_otherIdleNeteasePaused, .s5_otherIdleNeteasePlaying),
             (.s2_neteasePausedAsNowPlaying, .s1_neteasePlayingAsNowPlaying):
            // 用户手动恢复，清除软件暂停标记
            wasPausedByApp = false

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
        guard !isOtherAppPlaying else {
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
