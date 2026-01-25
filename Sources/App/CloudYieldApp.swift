//
//  CloudYieldApp.swift
//  CloudYield
//
//  应用程序主入口
//

import SwiftUI
import ServiceManagement
import AppKit

@main
struct CloudYieldApp: App {
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
    private var mediaMonitor: MediaMonitorProtocol?
    private var musicController: NeteaseMusicController?
    private var stateEngine: StateTransitionEngine?
    private var menuBarController: MenuBarController?
    private var permissionManager: PermissionManager?

    // 权限等待期间的状态栏
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logInfo("应用启动...", module: "App")
        logInfo("日志文件位置: \(Logger.shared.getLogFilePath())", module: "App")

        // 初始化权限管理器
        permissionManager = PermissionManager()

        // 立即创建状态栏图标（在等待权限期间显示）
        setupInitialStatusItem()

        guard #available(macOS 14.2, *) else {
            logError("当前系统版本不支持 Process Tap（需要 macOS 14.2+）", module: "App")
            updateInitialStatusItem(icon: "⚠️", text: "⚠️ 需要 macOS 14.2+（音频捕获）")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "系统版本不支持"
                alert.informativeText = "CloudYield 需要 macOS 14.2+ 才能通过 Process Tap 检测其他应用出声。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "退出")
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
            return
        }

        // 异步等待权限并初始化服务
        Task {
            // 等待辅助功能权限（用于 AppleScript 控制网易云）
            await checkAccessibilityPermission()

            // 权限授予后，初始化核心服务
            await MainActor.run {
                initializeServices()
            }
        }

        // 配置开机自启动（首次启动时提示用户）
        configureLaunchAtLogin()

        logSuccess("应用启动完成", module: "App")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("应用即将退出...", module: "App")

        // 停止媒体监控
        mediaMonitor?.stopMonitoring()
        stateEngine?.stop()

        // 清理资源
        cleanup()

        logInfo("应用已退出", module: "App")
    }

    // MARK: - Private Methods

    private func setupInitialStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "🎵"
        }

        // 创建简单菜单
        let menu = NSMenu()
        let statusMenuItem = NSMenuItem(title: "🎵 正在初始化...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    private func updateInitialStatusItem(icon: String, text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.title = icon
            if let menu = self?.statusItem?.menu, let firstItem = menu.items.first {
                firstItem.title = text
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func checkAccessibilityPermission() async {
        guard let permissionManager = permissionManager else { return }

        // 先检查一次，如果已有权限就不请求
        if permissionManager.hasAccessibilityPermission() {
            logSuccess("已有辅助功能权限", module: "App")
            return
        }

        // 更新托盘图标显示等待权限状态
        updateInitialStatusItem(icon: "⚠️", text: "⚠️ 等待辅助功能权限...")

        // 没有权限，只请求一次
        logWarning("缺少辅助功能权限，正在请求...", module: "App")
        permissionManager.requestAccessibilityPermission()

        // 持续检测直到有权限（不再重复请求）
        logInfo("等待用户授予辅助功能权限...", module: "App")
        logInfo("请在系统设置中勾选 CloudYield", module: "App")

        var attempts = 0
        while !permissionManager.hasAccessibilityPermission() {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            attempts += 1

            // 每5次检查输出一次日志
            if attempts % 5 == 0 {
                logDebug("权限检查第 \(attempts) 次：仍未授予", module: "App")
                // 更新托盘状态显示等待时间
                updateInitialStatusItem(icon: "⚠️", text: "⚠️ 等待辅助功能权限... (\(attempts)秒)")
            }

            // 每30秒提醒一次
            if attempts % 30 == 0 {
                logWarning("已等待 \(attempts) 秒，仍未检测到辅助功能权限", module: "App")
                logInfo("路径: 系统设置 → 隐私与安全性 → 辅助功能", module: "App")
            }
        }

        logSuccess("辅助功能权限已授予！（第 \(attempts) 次检查）", module: "App")

        // 恢复正常图标
        updateInitialStatusItem(icon: "🎵", text: "🎵 辅助功能权限已授予，初始化中...")
    }

    private func initializeServices() {
        // 移除初始状态栏（将由 MenuBarController 接管）
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        // 1. 初始化音乐控制器
        musicController = NeteaseMusicController()

        // 2. 初始化“其他应用出声”监控服务（Process Tap）
        if #available(macOS 14.2, *) {
            mediaMonitor = OtherAudioMonitor()
        }

        // 3. 初始化状态引擎
        if let musicController = musicController, let mediaMonitor = mediaMonitor {
            stateEngine = StateTransitionEngine(
                musicController: musicController,
                mediaMonitor: mediaMonitor
            )

            // 设置回调：音频状态变化 → 状态引擎
            mediaMonitor.onStatusChanged = { [weak self] status in
                self?.stateEngine?.onAudioStatusChanged(status: status)
            }
        }

        // 4. 初始化菜单栏控制器
        if let stateEngine = stateEngine {
            menuBarController = MenuBarController(stateEngine: stateEngine)
        }

        // 5. 启动音频监控
        mediaMonitor?.startMonitoring()

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
        alert.informativeText = "是否希望 CloudYield 在开机时自动启动？"
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
        statusItem = nil
    }
}
