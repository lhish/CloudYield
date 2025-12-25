//
//  MediaPlaybackMonitor.swift
//  StillMusicWhenBack
//
//  监控系统媒体播放状态 - 检测是否有其他应用在播放音频
//  不依赖音频捕获，直接通过 macOS 的 Now Playing 信息判断
//

import Foundation
import MediaPlayer
import AppKit

class MediaPlaybackMonitor: MediaMonitorProtocol {
    // MARK: - Properties

    private var monitorTimer: Timer?
    private var isMonitoring = false
    private let checkInterval: TimeInterval = 0.5 // 500ms 检查一次

    // 当前播放信息
    private var currentPlayingApp: String?
    private var isOtherAppPlaying = false

    // 回调：当检测到其他应用播放状态变化时
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    // MARK: - Public Methods

    /// 开始监控媒体播放状态
    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "MediaMonitor")
            return
        }

        logDebug("正在启动媒体播放监控...", module: "MediaMonitor")

        // 首次启动时，主动触发一次权限请求
        requestAutomationPermission()

        // 启动定时器定期检查
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkPlaybackStatus()
        }

        isMonitoring = true
        logSuccess("媒体播放监控已启动", module: "MediaMonitor")

        // 立即检查一次
        checkPlaybackStatus()
    }

    /// 主动请求自动化权限（会触发系统弹窗）
    private func requestAutomationPermission() {
        // 尝试访问多个应用以触发权限请求
        let appsToRequest = ["Music", "Spotify"]

        for appName in appsToRequest {
            let script = """
            tell application "\(appName)"
                if it is running then
                    return "running"
                end if
            end tell
            return "not_running"
            """

            guard let appleScript = NSAppleScript(source: script) else {
                continue
            }

            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                logInfo("触发 \(appName) 权限请求: \(error)", module: "MediaMonitor")
            } else {
                logSuccess("\(appName) 权限检查完成", module: "MediaMonitor")
            }
        }
    }

    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止媒体播放监控...", module: "MediaMonitor")

        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false

        logSuccess("媒体播放监控已停止", module: "MediaMonitor")
    }

    // MARK: - Private Methods

    private func checkPlaybackStatus() {
        let playingApps = getPlayingMediaApplications()

        logDebug("当前播放应用: \(playingApps.joined(separator: ", "))", module: "MediaMonitor")

        // 过滤掉网易云音乐
        let otherApps = playingApps.filter { app in
            !app.contains("NeteaseMusic") &&
            !app.contains("网易云音乐") &&
            !app.contains("NetEase")
        }

        let hasOtherAppPlaying = !otherApps.isEmpty

        // 如果状态发生变化，触发回调
        if hasOtherAppPlaying != isOtherAppPlaying {
            isOtherAppPlaying = hasOtherAppPlaying

            if hasOtherAppPlaying {
                logInfo("检测到其他应用正在播放: \(otherApps.joined(separator: ", "))", module: "MediaMonitor")
            } else {
                logInfo("其他应用已停止播放", module: "MediaMonitor")
            }

            DispatchQueue.main.async { [weak self] in
                self?.onOtherAppPlayingChanged?(hasOtherAppPlaying)
            }
        }
    }

    /// 获取当前正在播放媒体的应用列表
    private func getPlayingMediaApplications() -> [String] {
        var playingApps: [String] = []

        // 只检测专门的媒体应用,不检测浏览器
        // 因为浏览器需要 Automation 权限,且即使运行也不一定在播放
        let mediaApps = [
            "Music",           // Apple Music
            "Spotify",         // Spotify
            "IINA",            // IINA 视频播放器
            "VLC",             // VLC
            "QuickTime Player", // QuickTime
            "NeteaseMusic"     // 网易云音乐(稍后会被过滤掉)
        ]

        for appName in mediaApps {
            if isAppPlaying(appName) {
                playingApps.append(appName)
            }
        }

        return playingApps
    }

    /// 检查指定应用是否正在播放
    private func isAppPlaying(_ appName: String) -> Bool {
        // 首先检查应用是否在运行
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { app in
            app.localizedName == appName || app.bundleIdentifier?.contains(appName.replacingOccurrences(of: " ", with: "")) ?? false
        }

        guard isRunning else {
            return false
        }

        // 对于网易云音乐，使用 System Events 检查菜单状态
        if appName == "NeteaseMusic" {
            return checkNeteaseMusicPlaying()
        }

        // 对于其他媒体应用，通过 AppleScript 检查播放状态
        return checkPlayingViaAppleScript(appName)
    }

    /// 检查网易云音乐是否正在播放（通过菜单状态）
    private func checkNeteaseMusicPlaying() -> Bool {
        let script = """
        tell application "System Events"
            tell process "NeteaseMusic"
                try
                    set menuItemName to name of menu item 1 of menu "控制" of menu bar item "控制" of menu bar 1
                    return menuItemName
                on error
                    return "error"
                end try
            end tell
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error = error {
            logDebug("AppleScript 错误 (NeteaseMusic): \(error)", module: "MediaMonitor")
            return false
        }

        let menuItemName = result.stringValue ?? ""

        // 如果菜单显示"暂停"，说明正在播放
        let isPlaying = menuItemName == "暂停"

        if !menuItemName.isEmpty {
            logDebug("NeteaseMusic 菜单状态: \(menuItemName), 判定为播放: \(isPlaying)", module: "MediaMonitor")
        }

        return isPlaying
    }

    /// 检查浏览器是否在播放（通过检查标签页是否有音频图标）
    private func isBrowserPlaying(_ browserName: String) -> Bool {
        // 使用 Accessibility API 检查浏览器窗口
        // 这需要辅助功能权限

        // 简化版本：检查进程是否在使用音频设备
        // 这个方法不太准确，但不需要额外权限
        return false // 暂时禁用，后续可以优化
    }

    /// 通过 AppleScript 检查应用播放状态
    private func checkPlayingViaAppleScript(_ appName: String) -> Bool {
        var script = ""

        switch appName {
        case "Music":
            script = """
            tell application "Music"
                if it is running then
                    return player state as string
                end if
            end tell
            return "stopped"
            """

        case "Spotify":
            script = """
            tell application "Spotify"
                if it is running then
                    return player state as string
                end if
            end tell
            return "stopped"
            """

        case "IINA", "VLC":
            script = """
            tell application "\(appName)"
                if it is running then
                    return playing as string
                end if
            end tell
            return "false"
            """

        default:
            return false
        }

        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error = error {
            // 记录错误以便调试
            logDebug("AppleScript 错误 (\(appName)): \(error)", module: "MediaMonitor")
            return false
        }

        let state = result.stringValue ?? ""

        // 判断是否在播放
        let isPlaying = state.lowercased().contains("playing") || state.lowercased() == "true"

        if !state.isEmpty {
            logDebug("\(appName) 状态: \(state), 判定为播放: \(isPlaying)", module: "MediaMonitor")
        }

        return isPlaying
    }
}
