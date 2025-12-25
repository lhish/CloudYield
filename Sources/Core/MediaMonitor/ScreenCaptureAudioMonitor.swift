import Foundation

/// ScreenCaptureKit 音频监控适配器
/// 将 AudioMonitorService 适配到 MediaMonitorProtocol
class ScreenCaptureAudioMonitor: MediaMonitorProtocol {
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    private var audioMonitor: AudioMonitorService?

    init() {
        logInfo("ScreenCapture 音频监控器初始化", module: "ScreenCaptureMonitor")
        audioMonitor = AudioMonitorService()

        // 设置回调
        audioMonitor?.onAudioLevelChanged = { [weak self] hasSound in
            self?.onOtherAppPlayingChanged?(hasSound)
        }
    }

    func startMonitoring() {
        logInfo("启动 ScreenCapture 音频监控...", module: "ScreenCaptureMonitor")

        Task {
            do {
                try await audioMonitor?.startMonitoring()
                logSuccess("ScreenCapture 音频监控已启动", module: "ScreenCaptureMonitor")
            } catch {
                logError("启动失败: \(error)", module: "ScreenCaptureMonitor")
            }
        }
    }

    func stopMonitoring() {
        logInfo("停止 ScreenCapture 音频监控", module: "ScreenCaptureMonitor")
        audioMonitor?.stopMonitoring()
    }
}
