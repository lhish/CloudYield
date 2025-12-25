import Foundation

/// 多应用音频监控适配器
/// 将 MultiAppAudioMonitor 适配到 MediaMonitorProtocol 接口
class MultiAppAudioMonitorAdapter: MediaMonitorProtocol {
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    private var audioMonitor: MultiAppAudioMonitor

    init() {
        audioMonitor = MultiAppAudioMonitor()

        // 设置回调
        audioMonitor.onPlaybackStatusChanged = { [weak self] isPlaying in
            self?.onOtherAppPlayingChanged?(isPlaying)
        }

        logInfo("🎬 多应用音频监控适配器已初始化", module: "MultiAppMonitorAdapter")
    }

    func startMonitoring() {
        logInfo("▶️ 启动多应用音频监控...", module: "MultiAppMonitorAdapter")

        Task {
            do {
                try await audioMonitor.startMonitoring()
                logSuccess("✅ 多应用音频监控已启动", module: "MultiAppMonitorAdapter")

                // 打印监控摘要
                logInfo(audioMonitor.getMonitoringSummary(), module: "MultiAppMonitorAdapter")
            } catch {
                logError("❌ 启动失败: \(error)", module: "MultiAppMonitorAdapter")
            }
        }
    }

    func stopMonitoring() {
        logInfo("⏹️ 停止多应用音频监控", module: "MultiAppMonitorAdapter")

        Task {
            await audioMonitor.stopMonitoring()
        }
    }

    /// 获取正在播放的应用列表
    func getPlayingApplications() -> [String] {
        return audioMonitor.getPlayingApplications()
    }

    /// 获取监控摘要
    func getMonitoringSummary() -> String {
        return audioMonitor.getMonitoringSummary()
    }
}
