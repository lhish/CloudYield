//
//  MenuBarController.swift
//  StillMusicWhenBack
//
//  菜单栏控制器 - 管理状态栏图标和菜单
//

import AppKit
import SwiftUI

class MenuBarController: NSObject {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private let stateEngine: StateTransitionEngine
    private var menu: NSMenu?
    private var statusMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    // MARK: - Initialization

    init(stateEngine: StateTransitionEngine) {
        self.stateEngine = stateEngine
        super.init()

        setupMenuBar()
        observeStateChanges()
    }

    // MARK: - Private Methods

    private func setupMenuBar() {
        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 设置初始图标
        if let button = statusItem?.button {
            button.title = "🎵"
        }

        // 创建菜单
        createMenu()
    }

    private func createMenu() {
        menu = NSMenu()

        // 状态显示
        statusMenuItem = NSMenuItem(
            title: "正在监控中",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem?.isEnabled = false
        if let item = statusMenuItem {
            menu?.addItem(item)
        }

        menu?.addItem(NSMenuItem.separator())

        // 开机自启
        launchAtLoginMenuItem = NSMenuItem(
            title: "开机自启",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem?.target = self
        launchAtLoginMenuItem?.state = LaunchAtLoginManager.isEnabled ? .on : .off
        if let item = launchAtLoginMenuItem {
            menu?.addItem(item)
        }

        menu?.addItem(NSMenuItem.separator())

        // 打开日志目录
        let logItem = NSMenuItem(
            title: "打开日志目录",
            action: #selector(openLogDirectory),
            keyEquivalent: "l"
        )
        logItem.target = self
        menu?.addItem(logItem)

        // 打开音频捕获权限（Process Tap）
        let audioCaptureItem = NSMenuItem(
            title: "打开音频捕获权限",
            action: #selector(openAudioCaptureSettings),
            keyEquivalent: ""
        )
        audioCaptureItem.target = self
        menu?.addItem(audioCaptureItem)

        menu?.addItem(NSMenuItem.separator())

        // 关于
        let aboutItem = NSMenuItem(
            title: "关于 CloudYield",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        menu?.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        // 设置菜单
        self.statusItem?.menu = self.menu
    }

    private func observeStateChanges() {
        stateEngine.onStateChanged = { [weak self] newState in
            self?.updateUI(for: newState)
        }
    }

    private func updateUI(for state: AppState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateIcon(for: state)
            self?.updateStatusText(for: state)
        }
    }

    private func updateIcon(for state: AppState) {
        guard let button = statusItem?.button else { return }
        button.title = state.icon
    }

    private func updateStatusText(for state: AppState) {
        guard let statusMenuItem = statusMenuItem else { return }
        statusMenuItem.title = "\(state.icon) \(state.description)"
    }

    /// 公开方法：更新状态文本（用于显示权限等待等自定义状态）
    func updateStatusText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuItem?.title = text
        }
    }

    /// 公开方法：更新图标
    func updateIcon(_ icon: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.title = icon
        }
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.toggle()
        launchAtLoginMenuItem?.state = LaunchAtLoginManager.isEnabled ? .on : .off
        logInfo("开机自启: \(LaunchAtLoginManager.isEnabled ? "已启用" : "已禁用")", module: "MenuBar")
    }

    @objc private func openLogDirectory() {
        Logger.shared.openLogDirectory()
    }

    @objc private func openAudioCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "CloudYield"
        alert.informativeText = """
        版本: 1.2.0
        作者: lhish
        开源地址: github.com/lhish/CloudYield

        🎵 让网易云音乐更智能

        功能特性：
        • 检测到其他应用播放音频时自动暂停网易云
        • 其他应用停止播放并保持 2 秒静音后自动恢复网易云
        • 暂停触发 0.02 秒级别，恢复更稳不抖

        工作原理：
        • macOS 14.2+: 使用 Process Tap 检测其他应用出声
        • 使用 AppleScript 控制网易云音乐播放/暂停

        权限：
        • 辅助功能（控制网易云）
        • 音频捕获（检测其他应用出声）

        许可证: GPL-3.0 License
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.addButton(withTitle: "访问 GitHub")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/lhish/CloudYield") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quit() {
        logInfo("用户请求退出", module: "MenuBar")

        let alert = NSAlert()
        alert.messageText = "确认退出？"
        alert.informativeText = "退出后将停止监控"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
