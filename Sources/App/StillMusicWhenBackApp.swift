//
//  StillMusicWhenBackApp.swift
//  StillMusicWhenBack
//
//  应用程序主入口
//

import SwiftUI
import ServiceManagement

@main
struct StillMusicWhenBackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏应用不需要主窗口
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    // 核心服务
    private var mediaMonitor: MultiAppAudioMonitorAdapter?
    private var musicController: NeteaseMusicController?
    private var stateEngine: StateTransitionEngine?
    private var menuBarController: MenuBarController?
    private var permissionManager: PermissionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logInfo("应用启动...", module: "App")
        logInfo("日志文件位置: \(Logger.shared.getLogFilePath())", module: "App")

        // 初始化权限管理器
        permissionManager = PermissionManager()

        // 检查并请求屏幕录制权限（用于音频监控）
        Task {
            await checkScreenRecordingPermission()
        }

        // 检查并请求辅助功能权限（用于控制网易云音乐）
        Task {
            await checkAccessibilityPermission()
        }

        // 初始化核心服务
        initializeServices()

        // 配置开机自启动（首次启动时提示用户）
        configureLaunchAtLogin()

        logSuccess("应用启动完成", module: "App")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("应用即将退出...", module: "App")

        // 停止媒体监控
        mediaMonitor?.stopMonitoring()

        // 清理资源
        cleanup()

        logInfo("应用已退出", module: "App")
    }

    // MARK: - Private Methods

    private func checkScreenRecordingPermission() async {
        guard let permissionManager = permissionManager else { return }

        // 先检查一次，如果已有权限就不请求
        if permissionManager.hasScreenRecordingPermission() {
            logSuccess("已有屏幕录制权限", module: "App")
            return
        }

        // 没有权限，主动请求
        logWarning("缺少屏幕录制权限，正在请求...", module: "App")
        permissionManager.requestScreenRecordingPermission()

        // 等待用户授权
        logInfo("等待用户授予屏幕录制权限...", module: "App")
        logInfo("请在系统设置中勾选 StillMusicWhenBack", module: "App")

        var attempts = 0
        while !permissionManager.hasScreenRecordingPermission() {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            attempts += 1

            // 每5次检查输出一次日志
            if attempts % 5 == 0 {
                logDebug("屏幕录制权限检查第 \(attempts) 次：仍未授予", module: "App")
            }

            // 每30秒提醒一次
            if attempts % 30 == 0 {
                logWarning("已等待 \(attempts) 秒，仍未检测到屏幕录制权限", module: "App")
                logInfo("路径: 系统设置 → 隐私与安全性 → 屏幕录制", module: "App")
            }
        }

        logSuccess("屏幕录制权限已授予！（第 \(attempts) 次检查）", module: "App")
    }

    private func checkAccessibilityPermission() async {
        guard let permissionManager = permissionManager else { return }

        // 先检查一次，如果已有权限就不请求
        if permissionManager.hasAccessibilityPermission() {
            logSuccess("已有辅助功能权限", module: "App")
            return
        }

        // 更新托盘图标显示等待权限状态
        menuBarController?.updateIcon("⚠️")
        menuBarController?.updateStatusText("⚠️ 等待辅助功能权限...")

        // 没有权限，只请求一次
        logWarning("缺少辅助功能权限，正在请求...", module: "App")
        permissionManager.requestAccessibilityPermission()

        // 持续检测直到有权限（不再重复请求）
        logInfo("等待用户授予辅助功能权限...", module: "App")
        logInfo("请在系统设置中勾选 StillMusicWhenBack", module: "App")

        var attempts = 0
        while !permissionManager.hasAccessibilityPermission() {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            attempts += 1

            // 每5次检查输出一次日志
            if attempts % 5 == 0 {
                logDebug("权限检查第 \(attempts) 次：仍未授予", module: "App")
                // 更新托盘状态显示等待时间
                menuBarController?.updateStatusText("⚠️ 等待辅助功能权限... (\(attempts)秒)")
            }

            // 每30秒提醒一次
            if attempts % 30 == 0 {
                logWarning("已等待 \(attempts) 秒，仍未检测到辅助功能权限", module: "App")
                logInfo("路径: 系统设置 → 隐私与安全性 → 辅助功能", module: "App")
            }
        }

        logSuccess("辅助功能权限已授予！（第 \(attempts) 次检查）", module: "App")

        // 恢复正常图标
        menuBarController?.updateIcon("✅")
        menuBarController?.updateStatusText("✅ 辅助功能权限已授予")
    }

    private func showPermissionAlert() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "为了监控系统音频，需要授予屏幕录制权限。\n\n请前往：系统设置 → 隐私与安全性 → 屏幕录制，然后勾选 StillMusicWhenBack"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 打开系统设置
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func initializeServices() {
        // 1. 初始化音乐控制器
        musicController = NeteaseMusicController()

        // 2. 初始化多应用音频监控服务（基于 OBS 方案）
        mediaMonitor = MultiAppAudioMonitorAdapter()

        // 3. 初始化状态引擎
        if let musicController = musicController, let mediaMonitor = mediaMonitor {
            stateEngine = StateTransitionEngine(
                musicController: musicController,
                mediaMonitor: mediaMonitor
            )

            // 设置回调
            mediaMonitor.onOtherAppPlayingChanged = { [weak self] isPlaying in
                self?.stateEngine?.onOtherAppPlayingChanged(isPlaying: isPlaying)
            }
        }

        // 4. 初始化菜单栏控制器
        if let stateEngine = stateEngine {
            menuBarController = MenuBarController(stateEngine: stateEngine)
        }

        // 5. 启动多应用音频监控（自动监控所有应用）
        mediaMonitor?.startMonitoring()
        logSuccess("多应用音频监控已启动（基于 OBS 方案）", module: "App")

        // 6. 启动状态引擎
        stateEngine?.start()
        logSuccess("状态引擎已启动", module: "App")
    }

    private func configureLaunchAtLogin() {
        // 检查是否已经配置过开机自启动
        let hasConfigured = UserDefaults.standard.bool(forKey: "LaunchAtLoginConfigured")

        if !hasConfigured {
            // 首次启动，询问用户是否开机自启
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showLaunchAtLoginAlert()
            }
        }
    }

    private func showLaunchAtLoginAlert() {
        let alert = NSAlert()
        alert.messageText = "开机自启动"
        alert.informativeText = "是否希望 StillMusicWhenBack 在开机时自动启动？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "是")
        alert.addButton(withTitle: "否")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 启用开机自启动
            LaunchAtLoginManager.enable()
        }

        // 标记为已配置
        UserDefaults.standard.set(true, forKey: "LaunchAtLoginConfigured")
    }

    private func cleanup() {
        // 清理资源
        mediaMonitor = nil
        musicController = nil
        stateEngine = nil
        menuBarController = nil
        permissionManager = nil
    }
}
