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
        updateIcon(for: .monitoring)

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

        // 暂停/继续监控
        let pauseItem = NSMenuItem(
            title: "暂停监控",
            action: #selector(toggleMonitoring),
            keyEquivalent: "p"
        )
        pauseItem.target = self
        pauseItem.tag = 100 // 用于后续更新标题
        menu?.addItem(pauseItem)

        menu?.addItem(NSMenuItem.separator())

        // 打开日志目录
        let logItem = NSMenuItem(
            title: "打开日志目录",
            action: #selector(openLogDirectory),
            keyEquivalent: "l"
        )
        logItem.target = self
        menu?.addItem(logItem)

        menu?.addItem(NSMenuItem.separator())

        // 关于
        let aboutItem = NSMenuItem(
            title: "关于 StillMusicWhenBack",
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

    private func updateUI(for state: MonitorState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateIcon(for: state)
            self?.updateStatusText(for: state)
            self?.updatePauseMenuItem(for: state)
        }
    }

    private func updateIcon(for state: MonitorState) {
        guard let button = statusItem?.button else { return }

        // 根据状态设置不同的图标/符号
        let icon: String
        switch state {
        case .idle:
            icon = "🎵"
        case .monitoring:
            icon = "✅"
        case .detectingOtherSound:
            icon = "🔊"
        case .musicPaused:
            icon = "⏸"
        case .waitingResume:
            icon = "⏳"
        case .paused:
            icon = "⏹"
        }

        button.title = icon
    }

    private func updateStatusText(for state: MonitorState) {
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

    private func updatePauseMenuItem(for state: MonitorState) {
        guard let menu = menu,
              let pauseMenuItem = menu.item(withTag: 100) else { return }

        switch state {
        case .paused:
            pauseMenuItem.title = "继续监控"
        default:
            pauseMenuItem.title = "暂停监控"
        }
    }

    // MARK: - Actions

    @objc private func toggleMonitoring() {
        let currentState = stateEngine.getCurrentState()

        if currentState == .paused {
            stateEngine.resumeMonitoring()
        } else {
            stateEngine.pauseMonitoring()
        }
    }

    @objc private func openLogDirectory() {
        Logger.shared.openLogDirectory()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于 StillMusicWhenBack"
        alert.informativeText = """
        版本: 1.0.0

        功能：
        • 监控系统音频输出
        • 检测到其他声音时自动暂停网易云音乐
        • 声音停止后自动恢复播放

        使用方法：
        1. 确保已授予屏幕录制权限
        2. 播放网易云音乐
        3. 应用会在后台自动工作

        开发者: YourName
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    @objc private func quit() {
        logInfo("用户请求退出", module: "MenuBar")

        let alert = NSAlert()
        alert.messageText = "确认退出？"
        alert.informativeText = "退出后将停止监控系统音频"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
