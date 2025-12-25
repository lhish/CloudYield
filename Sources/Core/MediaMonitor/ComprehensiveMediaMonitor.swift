//
//  ComprehensiveMediaMonitor.swift
//  StillMusicWhenBack
//
//  综合媒体监控 - 结合多种方式检测所有应用的播放状态
//

import Foundation
import MediaPlayer
import AppKit
import CoreAudio

class ComprehensiveMediaMonitor: MediaMonitorProtocol {
    // MARK: - Properties

    private var monitorTimer: Timer?
    private var isMonitoring = false
    private let checkInterval: TimeInterval = 0.5

    private var isOtherAppPlaying = false
    private var lastPlayingApps: Set<String> = []

    // 回调
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "ComprehensiveMonitor")
            return
        }

        logDebug("正在启动综合媒体监控...", module: "ComprehensiveMonitor")

        // 启动定时器
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkAllPlayback()
        }

        isMonitoring = true
        logSuccess("综合媒体监控已启动", module: "ComprehensiveMonitor")

        // 立即检查一次
        checkAllPlayback()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止综合媒体监控...", module: "ComprehensiveMonitor")

        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false

        logSuccess("综合媒体监控已停止", module: "ComprehensiveMonitor")
    }

    // MARK: - Private Methods

    private func checkAllPlayback() {
        var allPlayingApps: Set<String> = []

        // 方法1: 检查专门的媒体应用(通过 AppleScript)
        let mediaApps = checkMediaApplications()
        allPlayingApps.formUnion(mediaApps)

        // 方法2: 检查使用音频设备的进程
        let audioProcesses = checkAudioProcesses()
        allPlayingApps.formUnion(audioProcesses)

        // 方法3: 检查 Now Playing Info
        if let nowPlayingApp = checkNowPlayingInfo() {
            allPlayingApps.insert(nowPlayingApp)
        }

        // 过滤掉网易云音乐
        let otherApps = allPlayingApps.filter { app in
            !app.contains("NeteaseMusic") &&
            !app.contains("网易云音乐") &&
            !app.contains("NetEase")
        }

        let hasOtherAppPlaying = !otherApps.isEmpty

        // 检测变化
        if otherApps != lastPlayingApps {
            lastPlayingApps = otherApps

            if !otherApps.isEmpty {
                logInfo("检测到应用正在播放: \(otherApps.joined(separator: ", "))", module: "ComprehensiveMonitor")
            } else {
                logDebug("没有其他应用播放", module: "ComprehensiveMonitor")
            }
        }

        // 状态变化回调
        if hasOtherAppPlaying != isOtherAppPlaying {
            isOtherAppPlaying = hasOtherAppPlaying

            if hasOtherAppPlaying {
                logInfo("其他应用开始播放", module: "ComprehensiveMonitor")
            } else {
                logInfo("其他应用停止播放", module: "ComprehensiveMonitor")
            }

            DispatchQueue.main.async { [weak self] in
                self?.onOtherAppPlayingChanged?(hasOtherAppPlaying)
            }
        }
    }

    // MARK: - Detection Methods

    /// 方法1: 检查专门的媒体应用
    private func checkMediaApplications() -> Set<String> {
        var playingApps: Set<String> = []

        // 检查网易云音乐(通过菜单)
        if checkNeteaseMusicPlaying() {
            playingApps.insert("NeteaseMusic")
        }

        // 其他媒体应用暂时跳过,因为需要 Automation 权限
        // TODO: 用户授权后可以添加 Music, Spotify 等

        return playingApps
    }

    /// 方法2: 检查哪些进程正在使用音频设备
    private func checkAudioProcesses() -> Set<String> {
        var playingApps: Set<String> = []

        // 获取所有运行中的应用
        let runningApps = NSWorkspace.shared.runningApplications

        // 常见的媒体应用 Bundle IDs
        let mediaAppBundleIDs: [String: String] = [
            "com.apple.Music": "Apple Music",
            "com.spotify.client": "Spotify",
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Chrome",
            "org.mozilla.firefox": "Firefox",
            "com.microsoft.edgemac": "Edge",
            "com.colliderli.iina": "IINA",
            "org.videolan.vlc": "VLC",
            "com.apple.QuickTimePlayerX": "QuickTime",
            "com.netease.163music": "NeteaseMusic"
        ]

        // 启发式检测:检查活跃的媒体应用
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let appName = mediaAppBundleIDs[bundleID] else {
                continue
            }

            // 对于浏览器:只有活跃(在前台)才算
            let isBrowser = ["Safari", "Chrome", "Firefox", "Edge"].contains(appName)
            if isBrowser {
                if app.isActive {
                    playingApps.insert(appName)
                    logDebug("检测到活跃浏览器: \(appName)", module: "ComprehensiveMonitor")
                }
            }
            // 对于专门的媒体应用:运行中且未隐藏就算
            else if !app.isHidden {
                playingApps.insert(appName)
                logDebug("检测到媒体应用: \(appName)", module: "ComprehensiveMonitor")
            }
        }

        return playingApps
    }

    /// 方法3: 检查 Now Playing Info
    private func checkNowPlayingInfo() -> String? {
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo

        if let info = nowPlayingInfo,
           let title = info[MPMediaItemPropertyTitle] as? String {
            logDebug("Now Playing: \(title)", module: "ComprehensiveMonitor")
            // 无法获取应用名,但至少知道有东西在播放
            return "Unknown App (Now Playing)"
        }

        return nil
    }

    // MARK: - Helper Methods

    /// 检查网易云音乐是否正在播放
    private func checkNeteaseMusicPlaying() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "NeteaseMusic") then
                return "not_running"
            end if
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
            logDebug("检查网易云失败: \(error)", module: "ComprehensiveMonitor")
            return false
        }

        let menuItemName = result.stringValue ?? ""
        return menuItemName == "暂停"  // "暂停" = 正在播放
    }
}
