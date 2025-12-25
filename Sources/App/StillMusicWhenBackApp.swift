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
    private var audioMonitor: AudioMonitorService?
    private var musicController: NeteaseMusicController?
    private var stateEngine: StateTransitionEngine?
    private var menuBarController: MenuBarController?
    private var permissionManager: PermissionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] 应用启动...")

        // 初始化权限管理器
        permissionManager = PermissionManager()

        // 检查并请求必要权限
        Task {
            await checkPermissions()
        }

        // 初始化核心服务
        initializeServices()

        // 配置开机自启动（首次启动时提示用户）
        configureLaunchAtLogin()

        print("[App] 应用启动完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[App] 应用即将退出...")

        // 停止音频监控
        audioMonitor?.stopMonitoring()

        // 清理资源
        cleanup()

        print("[App] 应用已退出")
    }

    // MARK: - Private Methods

    private func checkPermissions() async {
        guard let permissionManager = permissionManager else { return }

        // 检查屏幕录制权限（用于捕获系统音频）
        if !permissionManager.hasScreenRecordingPermission() {
            print("[App] ⚠️  缺少屏幕录制权限，正在请求...")

            // 自动请求权限
            permissionManager.requestScreenRecordingPermission()

            // 等待一小段时间让系统显示权限对话框
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒

            // 再次检查权限
            if !permissionManager.hasScreenRecordingPermission() {
                print("[App] ⚠️  仍缺少屏幕录制权限，显示设置指引")
                await showPermissionAlert()
            } else {
                print("[App] ✅ 屏幕录制权限已授予")
            }
        } else {
            print("[App] ✅ 已有屏幕录制权限")
        }

        // 检查辅助功能权限（用于控制网易云音乐）
        if !permissionManager.hasAccessibilityPermission() {
            print("[App] ⚠️  缺少辅助功能权限，正在请求...")

            // 自动请求权限（会弹出系统对话框）
            permissionManager.requestAccessibilityPermission()

            // 等待一小段时间
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            if permissionManager.hasAccessibilityPermission() {
                print("[App] ✅ 辅助功能权限已授予")
            } else {
                print("[App] 💡 请在系统设置中授予辅助功能权限")
                print("[App] 💡 路径: 系统设置 → 隐私与安全性 → 辅助功能")
            }
        } else {
            print("[App] ✅ 已有辅助功能权限")
        }
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

        // 2. 初始化音频监控服务
        audioMonitor = AudioMonitorService()

        // 3. 初始化状态引擎
        if let musicController = musicController, let audioMonitor = audioMonitor {
            stateEngine = StateTransitionEngine(
                musicController: musicController,
                audioMonitor: audioMonitor
            )

            // 设置回调
            audioMonitor.onAudioLevelChanged = { [weak self] hasSignificantSound in
                self?.stateEngine?.onAudioLevelChanged(hasSound: hasSignificantSound)
            }
        }

        // 4. 初始化菜单栏控制器
        if let stateEngine = stateEngine {
            menuBarController = MenuBarController(stateEngine: stateEngine)
        }

        // 5. 启动音频监控
        Task {
            do {
                try await audioMonitor?.startMonitoring()
                print("[App] ✅ 音频监控已启动")
            } catch {
                print("[App] ❌ 音频监控启动失败: \(error)")
            }
        }

        // 6. 启动状态引擎
        stateEngine?.start()
        print("[App] ✅ 状态引擎已启动")
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
        audioMonitor = nil
        musicController = nil
        stateEngine = nil
        menuBarController = nil
        permissionManager = nil
    }
}
