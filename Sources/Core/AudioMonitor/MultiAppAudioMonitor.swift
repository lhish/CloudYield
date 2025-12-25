import Foundation
import ScreenCaptureKit
import AppKit

/// 多应用音频监控管理器
/// 管理多个 AppAudioStream 实例，聚合音量数据
class MultiAppAudioMonitor {
    // MARK: - Properties

    private var appStreams: [String: AppAudioStream] = [:]  // bundleID -> stream
    private var applicationVolumes: [String: Float] = [:]   // bundleID -> volume (dB)
    private var monitoredAppBundleIDs: Set<String> = []

    private var isMonitoring = false
    private let updateQueue = DispatchQueue(label: "com.stillmusic.multiapp.update")

    // 动态监控：只监控前台应用 + 最近使用的应用
    private var recentApps: [String: Date] = [:]  // bundleID -> 最后活跃时间
    private let recentAppTimeout: TimeInterval = 30.0  // 30秒内使用过的应用
    private var currentFrontmostApp: String?
    private var workspaceObserver: NSObjectProtocol?

    // 配置
    private let volumeThreshold: Float = -40.0  // dB，低于此值视为无声
    private let startupTimeout: TimeInterval = 5.0  // 每个应用启动超时时间（秒）

    // 白名单：常见的音频/视频应用（只监控这些应用以降低资源占用）
    private let audioAppWhitelist: Set<String> = [
        // 音乐播放器
        "com.netease.163music",
        "com.netease.Music",
        "com.netease.CloudMusic",
        "com.apple.Music",
        "com.spotify.client",
        "com.qq.QQMusic",

        // 视频播放器
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.apple.TV",
        "com.tencent.tenvideo",
        "com.iqiyi.player",

        // 浏览器（可能播放视频/音乐）
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",

        // 通讯软件
        "com.tencent.xinWeChat",
        "com.tencent.qq",
        "com.skype.skype",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.tencent.meeting",

        // 其他常见音频应用
        "com.bilibili.mac",
        "tv.douyu.DouyuLive",
        "com.electron.neteasemusic"
    ]

    // 黑名单：已知不支持音频捕获或会导致卡顿的应用
    private let blacklistedBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.github.atom",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.webstorm",
        "com.apple.dt.Xcode",
        // 系统辅助进程（会导致崩溃）
        "com.apple.nsattributedstringagent",
        "com.apple.CursorUIViewService",
        "com.apple.TextInputSwitcher",
        "com.apple.dock"  // 程序坞
    ]

    // 回调
    var onPlaybackStatusChanged: ((Bool) -> Void)?  // 是否有其他应用在播放

    // MARK: - Public Methods

    /// 设置要监控的应用列表
    func setMonitoredApplications(_ bundleIDs: [String]) {
        monitoredAppBundleIDs = Set(bundleIDs)
        logInfo("📋 设置监控应用列表: \(bundleIDs.joined(separator: ", "))", module: "MultiAppMonitor")
    }

    /// 开始监控（动态模式：只监控前台应用 + 最近使用的应用）
    func startMonitoring() async throws {
        guard !isMonitoring else {
            logInfo("ℹ️ 已经在监控中", module: "MultiAppMonitor")
            return
        }

        logInfo("🚀 开始动态音频监控（只监控前台应用）...", module: "MultiAppMonitor")

        // 设置应用切换监听
        setupAppSwitchObserver()

        // 获取当前前台应用并开始监控
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmostApp.bundleIdentifier {
            currentFrontmostApp = bundleID
            await startMonitoringBundleID(bundleID)
        }

        isMonitoring = true
        logSuccess("🎉 动态音频监控已启动", module: "MultiAppMonitor")
    }

    /// 停止监控
    func stopMonitoring() async {
        guard isMonitoring else { return }

        logInfo("⏹️ 停止动态音频监控...", module: "MultiAppMonitor")

        // 移除应用切换监听器
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        for stream in appStreams.values {
            await stream.stopCapture()
        }

        appStreams.removeAll()
        applicationVolumes.removeAll()
        recentApps.removeAll()
        currentFrontmostApp = nil
        isMonitoring = false

        logSuccess("✅ 动态音频监控已停止", module: "MultiAppMonitor")
    }

    /// 获取所有应用的音量（内部方法，假设已在 updateQueue 中）
    private func getApplicationVolumesUnsafe() -> [String: Float] {
        return applicationVolumes
    }

    /// 获取所有应用的音量（外部调用，线程安全）
    func getApplicationVolumes() -> [String: Float] {
        return updateQueue.sync {
            return applicationVolumes
        }
    }

    /// 检查是否有其他应用在播放（内部方法，假设已在 updateQueue 中）
    private func hasOtherAppPlayingUnsafe() -> Bool {
        let volumes = applicationVolumes

        // 排除网易云音乐
        let otherAppsPlaying = volumes.filter { bundleID, volume in
            !isNeteaseMusicApp(bundleID) && volume > volumeThreshold
        }

        return !otherAppsPlaying.isEmpty
    }

    /// 检查是否有其他应用在播放（外部调用，线程安全）
    func hasOtherAppPlaying() -> Bool {
        return updateQueue.sync {
            return hasOtherAppPlayingUnsafe()
        }
    }

    /// 获取正在播放的应用名称（内部方法，假设已在 updateQueue 中）
    private func getPlayingApplicationsUnsafe() -> [String] {
        let volumes = applicationVolumes

        return volumes.compactMap { bundleID, volume in
            guard volume > volumeThreshold,
                  !isNeteaseMusicApp(bundleID),
                  let stream = appStreams[bundleID] else {
                return nil
            }
            return stream.application.applicationName
        }
    }

    /// 获取正在播放的应用名称（外部调用，线程安全）
    func getPlayingApplications() -> [String] {
        return updateQueue.sync {
            return getPlayingApplicationsUnsafe()
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

    /// 启动单个应用的监控（带超时）
    private func startMonitoringApp(_ app: SCRunningApplication) async -> (String, AppAudioStream?) {
        let bundleID = app.bundleIdentifier
        let appName = app.applicationName

        logInfo("🎵 开始捕获应用音频: \(appName)", module: "AppAudioStream")

        let stream = AppAudioStream(application: app)

        // 设置音量变化回调
        stream.onVolumeChanged = { [weak self] volume in
            self?.handleVolumeChanged(bundleID: bundleID, volume: volume)
        }

        // 使用超时机制启动捕获
        do {
            try await withTimeout(seconds: startupTimeout) {
                try await stream.startCapture()
            }
            logSuccess("✅ 成功启动监控: \(appName) (\(bundleID))", module: "MultiAppMonitor")
            return (bundleID, stream)
        } catch {
            if error is TimeoutError {
                logWarning("⏱️ 启动超时: \(appName) (\(bundleID))", module: "MultiAppMonitor")
            } else {
                logError("❌ 启动失败: \(appName) - \(error)", module: "MultiAppMonitor")
            }
            return (bundleID, nil)
        }
    }

    /// 超时错误
    private struct TimeoutError: Error {}

    /// 带超时的异步操作
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask {
                try await operation()
            }

            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            // 等待第一个完成的任务
            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            // 取消其他任务
            group.cancelAll()

            return result
        }
    }

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
        // 注意：此方法假设已在 updateQueue 中调用
        let hasPlaying = hasOtherAppPlayingUnsafe()
        let playingApps = getPlayingApplicationsUnsafe()

        if hasPlaying {
            logInfo("▶️ 检测到其他应用正在播放: \(playingApps.joined(separator: ", "))", module: "MultiAppMonitor")
        } else {
            logDebug("⏸️ 没有其他应用正在播放", module: "MultiAppMonitor")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackStatusChanged?(hasPlaying)
        }
    }

    // MARK: - 动态监控方法

    /// 设置应用切换监听
    private func setupAppSwitchObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            Task {
                await self?.handleAppSwitch(to: bundleID)
            }
        }
        logInfo("👀 已设置应用切换监听", module: "MultiAppMonitor")
    }

    /// 处理应用切换
    private func handleAppSwitch(to newBundleID: String) async {
        guard isMonitoring else { return }

        // 跳过自己和网易云音乐
        guard newBundleID != Bundle.main.bundleIdentifier,
              !isNeteaseMusicApp(newBundleID) else {
            return
        }

        logInfo("🔄 应用切换到: \(newBundleID)", module: "MultiAppMonitor")

        // 1. 将旧的前台应用加入最近使用列表
        if let oldApp = currentFrontmostApp, oldApp != newBundleID {
            recentApps[oldApp] = Date()
        }
        currentFrontmostApp = newBundleID

        // 2. 清理过期的最近应用
        let now = Date()
        recentApps = recentApps.filter { now.timeIntervalSince($0.value) < recentAppTimeout }

        // 3. 计算需要监控的应用列表
        var appsToMonitor = Set<String>()
        appsToMonitor.insert(newBundleID)  // 当前前台应用
        appsToMonitor.formUnion(recentApps.keys)  // 最近使用的应用

        // 4. 排除网易云音乐和自己
        appsToMonitor = appsToMonitor.filter {
            !isNeteaseMusicApp($0) && $0 != Bundle.main.bundleIdentifier
        }

        // 5. 切换监控目标
        await switchMonitoringTo(appsToMonitor)
    }

    /// 切换监控目标
    private func switchMonitoringTo(_ targetBundleIDs: Set<String>) async {
        let currentMonitored = Set(appStreams.keys)

        // 1. 停止不再需要监控的应用
        let toStop = currentMonitored.subtracting(targetBundleIDs)
        for bundleID in toStop {
            if let stream = appStreams[bundleID] {
                logInfo("⏹️ 停止监控: \(bundleID)", module: "MultiAppMonitor")
                await stream.stopCapture()
                appStreams.removeValue(forKey: bundleID)
                updateQueue.async { [weak self] in
                    self?.applicationVolumes.removeValue(forKey: bundleID)
                }
            }
        }

        // 2. 启动新需要监控的应用
        let toStart = targetBundleIDs.subtracting(currentMonitored)
        for bundleID in toStart {
            await startMonitoringBundleID(bundleID)
        }

        logDebug("📊 当前监控: \(appStreams.count) 个应用", module: "MultiAppMonitor")
    }

    /// 根据 bundleID 启动监控
    private func startMonitoringBundleID(_ bundleID: String) async {
        // 跳过黑名单应用
        guard !blacklistedBundleIDs.contains(bundleID) else {
            logDebug("⏭️ 跳过黑名单应用: \(bundleID)", module: "MultiAppMonitor")
            return
        }

        // 查找 SCRunningApplication
        guard let app = await findRunningApplication(bundleID: bundleID) else {
            logDebug("⚠️ 找不到应用: \(bundleID)", module: "MultiAppMonitor")
            return
        }

        // 启动监控
        let (_, stream) = await startMonitoringApp(app)
        if let stream = stream {
            appStreams[bundleID] = stream
        }
    }

    /// 查找运行中的应用
    private func findRunningApplication(bundleID: String) async -> SCRunningApplication? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        return content?.applications.first { $0.bundleIdentifier == bundleID }
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
