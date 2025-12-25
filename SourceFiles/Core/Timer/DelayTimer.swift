//
//  DelayTimer.swift
//  StillMusicWhenBack
//
//  延迟计时器 - 实现精确的 3 秒延迟计时
//

import Foundation

class DelayTimer {
    // MARK: - Properties

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.stillmusic.timer", qos: .userInteractive)
    private let delay: TimeInterval
    private var isRunning = false

    // 回调
    var onTimerExpired: (() -> Void)?

    // MARK: - Initialization

    init(delay: TimeInterval = 3.0) {
        self.delay = delay
    }

    // MARK: - Public Methods

    /// 启动计时器
    func start() {
        guard !isRunning else {
            print("[DelayTimer] 计时器已经在运行中")
            return
        }

        // 取消之前的计时器（如果有）
        stop()

        print("[DelayTimer] 启动计时器，延迟 \(delay) 秒")

        // 创建新的计时器
        timer = DispatchSource.makeTimerSource(queue: queue)

        timer?.schedule(
            deadline: .now() + delay,
            repeating: .never
        )

        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }

            print("[DelayTimer] ⏰ 计时器到期")

            // 在主线程触发回调
            DispatchQueue.main.async {
                self.onTimerExpired?()
            }

            self.isRunning = false
        }

        timer?.resume()
        isRunning = true
    }

    /// 停止并重置计时器
    func stop() {
        guard isRunning else { return }

        print("[DelayTimer] 停止计时器")

        timer?.cancel()
        timer = nil
        isRunning = false
    }

    /// 重启计时器（先停止再启动）
    func restart() {
        print("[DelayTimer] 重启计时器")
        stop()
        start()
    }

    /// 检查计时器是否正在运行
    func isActive() -> Bool {
        return isRunning
    }

    // MARK: - Deinitialization

    deinit {
        stop()
    }
}
