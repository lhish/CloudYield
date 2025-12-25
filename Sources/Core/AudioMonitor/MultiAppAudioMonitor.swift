import Foundation
import ScreenCaptureKit

/// 多应用音频监控管理器
/// 管理多个 AppAudioStream 实例，聚合音量数据
class MultiAppAudioMonitor {
    // MARK: - Properties

    private var appStreams: [String: AppAudioStream] = [:]  // bundleID -> stream
    private var applicationVolumes: [String: Float] = [:]   // bundleID -> volume (dB)
    private var monitoredAppBundleIDs: Set<String> = []

    private var isMonitoring = false
    private let updateQueue = DispatchQueue(label: "com.stillmusic.multiapp.update")

    // 配置
    private let volumeThreshold: Float = -40.0  // dB，低于此值视为无声

    // 回调
    var onPlaybackStatusChanged: ((Bool) -> Void)?  // 是否有其他应用在播放

    // MARK: - Public Methods

    /// 设置要监控的应用列表
    func setMonitoredApplications(_ bundleIDs: [String]) {
        monitoredAppBundleIDs = Set(bundleIDs)
        logInfo("📋 设置监控应用列表: \(bundleIDs.joined(separator: ", "))", module: "MultiAppMonitor")
    }

    /// 开始监控
    func startMonitoring() async throws {
        guard !isMonitoring else {
            logInfo("ℹ️ 已经在监控中", module: "MultiAppMonitor")
            return
        }

        logInfo("🚀 开始多应用音频监控...", module: "MultiAppMonitor")

        // 获取所有可用应用
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        logDebug("找到 \(content.applications.count) 个运行中的应用", module: "MultiAppMonitor")

        // 自动监控所有应用（排除自己和系统应用）
        let appsToMonitor = content.applications.filter { app in
            !app.bundleIdentifier.isEmpty &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier &&
            !app.bundleIdentifier.hasPrefix("com.apple.systemuiserver") &&
            !app.bundleIdentifier.hasPrefix("com.apple.controlcenter") &&
            !app.bundleIdentifier.hasPrefix("com.apple.finder") &&
            !isNeteaseMusicApp(app.bundleIdentifier)  // 也排除网易云音乐
        }

        logInfo("🎯 将自动监控 \(appsToMonitor.count) 个应用", module: "MultiAppMonitor")

        // 为每个应用创建音频流
        for app in appsToMonitor {
            let stream = AppAudioStream(application: app)

            // 设置音量变化回调
            stream.onVolumeChanged = { [weak self] volume in
                self?.handleVolumeChanged(bundleID: app.bundleIdentifier, volume: volume)
            }

            // 启动捕获
            do {
                try await stream.startCapture()
                appStreams[app.bundleIdentifier] = stream
                logSuccess("✅ 成功启动监控: \(app.applicationName) (\(app.bundleIdentifier))", module: "MultiAppMonitor")
            } catch {
                logError("❌ 启动失败: \(app.applicationName) - \(error)", module: "MultiAppMonitor")
            }
        }

        isMonitoring = true
        logSuccess("🎉 多应用音频监控已启动，正在监控 \(appStreams.count) 个应用", module: "MultiAppMonitor")
    }

    /// 停止监控
    func stopMonitoring() async {
        guard isMonitoring else { return }

        logInfo("⏹️ 停止多应用音频监控...", module: "MultiAppMonitor")

        for stream in appStreams.values {
            await stream.stopCapture()
        }

        appStreams.removeAll()
        applicationVolumes.removeAll()
        isMonitoring = false

        logSuccess("✅ 多应用音频监控已停止", module: "MultiAppMonitor")
    }

    /// 获取所有应用的音量
    func getApplicationVolumes() -> [String: Float] {
        return updateQueue.sync {
            return applicationVolumes
        }
    }

    /// 检查是否有其他应用在播放
    func hasOtherAppPlaying() -> Bool {
        let volumes = getApplicationVolumes()

        // 排除网易云音乐
        let otherAppsPlaying = volumes.filter { bundleID, volume in
            !isNeteaseMusicApp(bundleID) && volume > volumeThreshold
        }

        return !otherAppsPlaying.isEmpty
    }

    /// 获取正在播放的应用名称
    func getPlayingApplications() -> [String] {
        let volumes = getApplicationVolumes()

        return volumes.compactMap { bundleID, volume in
            guard volume > volumeThreshold,
                  !isNeteaseMusicApp(bundleID),
                  let stream = appStreams[bundleID] else {
                return nil
            }
            return stream.application.applicationName
        }
    }

    /// 获取监控状态摘要
    func getMonitoringSummary() -> String {
        let volumes = getApplicationVolumes()
        let activeApps = volumes.filter { $0.value > volumeThreshold }

        return """
        监控状态:
        - 正在监控: \(appStreams.count) 个应用
        - 活跃应用: \(activeApps.count) 个
        - 正在播放: \(getPlayingApplications().joined(separator: ", "))
        """
    }

    // MARK: - Private Methods

    private func handleVolumeChanged(bundleID: String, volume: Float) {
        updateQueue.async { [weak self] in
            guard let self = self else { return }

            let oldVolume = self.applicationVolumes[bundleID] ?? -100.0
            self.applicationVolumes[bundleID] = volume

            // 检查播放状态是否改变
            let wasPlaying = oldVolume > self.volumeThreshold
            let isPlaying = volume > self.volumeThreshold

            if wasPlaying != isPlaying {
                // 某个应用的播放状态改变，检查总体状态
                logDebug("[\(bundleID)] 播放状态改变: \(wasPlaying) -> \(isPlaying)", module: "MultiAppMonitor")
                self.checkAndNotifyPlaybackStatus()
            }
        }
    }

    private func checkAndNotifyPlaybackStatus() {
        let hasPlaying = hasOtherAppPlaying()
        let playingApps = getPlayingApplications()

        if hasPlaying {
            logInfo("▶️ 检测到其他应用正在播放: \(playingApps.joined(separator: ", "))", module: "MultiAppMonitor")
        } else {
            logDebug("⏸️ 没有其他应用正在播放", module: "MultiAppMonitor")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackStatusChanged?(hasPlaying)
        }
    }

    /// 判断是否是网易云音乐应用
    private func isNeteaseMusicApp(_ bundleID: String) -> Bool {
        let neteaseBundleIDs = [
            "com.netease.163music",
            "com.netease.Music",
            "com.netease.CloudMusic"
        ]

        return neteaseBundleIDs.contains(bundleID) ||
               bundleID.lowercased().contains("netease") ||
               bundleID.lowercased().contains("163music")
    }
}
