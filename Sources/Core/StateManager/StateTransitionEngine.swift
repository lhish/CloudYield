//
//  StateTransitionEngine.swift
//  StillMusicWhenBack
//
//  状态转换引擎 - 协调音频检测和音乐控制
//

import Foundation

class StateTransitionEngine {
    // MARK: - Properties

    private var currentState: MonitorState = .idle
    private let musicController: NeteaseMusicController
    private let audioMonitor: AudioMonitorService

    // 计时器
    private var detectTimer: DelayTimer?      // 检测其他声音的计时器
    private var resumeTimer: DelayTimer?      // 恢复播放的计时器

    // 缓存网易云之前是否在播放
    private var wasMusicPlayingBeforePause = false

    // 状态变化回调
    var onStateChanged: ((MonitorState) -> Void)?

    // MARK: - Initialization

    init(musicController: NeteaseMusicController, audioMonitor: AudioMonitorService) {
        self.musicController = musicController
        self.audioMonitor = audioMonitor

        // 初始化计时器
        detectTimer = DelayTimer(delay: 3.0)
        resumeTimer = DelayTimer(delay: 3.0)

        // 设置计时器回调
        detectTimer?.onTimerExpired = { [weak self] in
            self?.onDetectTimerExpired()
        }

        resumeTimer?.onTimerExpired = { [weak self] in
            self?.onResumeTimerExpired()
        }
    }

    // MARK: - Public Methods

    /// 启动状态引擎
    func start() {
        logInfo("启动状态引擎", module: "StateEngine")
        transitionTo(.monitoring)
    }

    /// 停止状态引擎
    func stop() {
        logInfo("停止状态引擎", module: "StateEngine")
        detectTimer?.stop()
        resumeTimer?.stop()
        transitionTo(.idle)
    }

    /// 暂停监控（用户手动）
    func pauseMonitoring() {
        logInfo("用户暂停监控", module: "StateEngine")
        detectTimer?.stop()
        resumeTimer?.stop()
        transitionTo(.paused)
    }

    /// 恢复监控（用户手动）
    func resumeMonitoring() {
        logInfo("用户恢复监控", module: "StateEngine")
        transitionTo(.monitoring)
    }

    /// 音频级别变化回调
    func onAudioLevelChanged(hasSound: Bool) {
        logDebug("收到音频级别变化回调，hasSound: \(hasSound)", module: "StateEngine")
        handleAudioLevelChange(hasSound: hasSound)
    }

    /// 获取当前状态
    func getCurrentState() -> MonitorState {
        return currentState
    }

    // MARK: - Private Methods - State Machine

    private func handleAudioLevelChange(hasSound: Bool) {
        switch currentState {
        case .monitoring:
            if hasSound {
                // 检测到声音，开始计时
                logInfo("检测到声音，开始计时...", module: "StateEngine")
                detectTimer?.start()
                transitionTo(.detectingOtherSound)
            }

        case .detectingOtherSound:
            if !hasSound {
                // 声音消失，取消计时
                logInfo("声音消失，取消计时", module: "StateEngine")
                detectTimer?.stop()
                transitionTo(.monitoring)
            }
            // 如果声音持续，等待计时器到期

        case .musicPaused:
            if !hasSound {
                // 其他声音停止，开始恢复计时
                logInfo("其他声音停止，开始恢复计时...", module: "StateEngine")
                resumeTimer?.start()
                transitionTo(.waitingResume)
            }

        case .waitingResume:
            if hasSound {
                // 再次检测到声音，取消恢复
                logInfo("再次检测到声音，取消恢复", module: "StateEngine")
                resumeTimer?.stop()
                transitionTo(.musicPaused)
            }
            // 如果声音持续安静，等待计时器到期

        case .idle, .paused:
            // 这些状态不处理音频变化
            break
        }
    }

    private func onDetectTimerExpired() {
        logInfo("⏰ 检测计时器到期", module: "StateEngine")

        guard currentState == .detectingOtherSound else { return }

        // 检查网易云是否正在播放
        if musicController.isPlaying() {
            logInfo("网易云正在播放，准备暂停...", module: "StateEngine")
            wasMusicPlayingBeforePause = true

            // 暂停网易云
            musicController.pause()

            transitionTo(.musicPaused)
        } else {
            logInfo("网易云未在播放，不需要操作", module: "StateEngine")
            wasMusicPlayingBeforePause = false
            transitionTo(.monitoring)
        }
    }

    private func onResumeTimerExpired() {
        logInfo("⏰ 恢复计时器到期", module: "StateEngine")

        guard currentState == .waitingResume else { return }

        // 只有之前网易云在播放，才恢复
        if wasMusicPlayingBeforePause {
            logInfo("恢复网易云播放...", module: "StateEngine")
            musicController.play()
            wasMusicPlayingBeforePause = false
        } else {
            logInfo("网易云之前未在播放，不恢复", module: "StateEngine")
        }

        transitionTo(.monitoring)
    }

    private func transitionTo(_ newState: MonitorState) {
        let oldState = currentState
        currentState = newState

        logInfo("状态变化: \(oldState.description) → \(newState.description)", module: "StateEngine")

        // 触发状态变化回调
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(newState)
        }
    }
}
