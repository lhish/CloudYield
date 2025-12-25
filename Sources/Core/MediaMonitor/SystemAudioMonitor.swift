//
//  SystemAudioMonitor.swift
//  StillMusicWhenBack
//
//  监控系统级别的音频播放状态
//  使用 MediaRemote 私有 API (仅用于检测,不用于控制)
//  以及 NSWorkspace 通知来检测媒体播放
//

import Foundation
import MediaPlayer
import AppKit

class SystemAudioMonitor: MediaMonitorProtocol {
    // MARK: - Properties

    private var isMonitoring = false
    private var monitorTimer: Timer?
    private let checkInterval: TimeInterval = 0.5

    private var isOtherAppPlaying = false
    private var lastPlayingApp: String?

    // 回调：当检测到其他应用播放状态变化时
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    // MARK: - Public Methods

    /// 开始监控
    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "SystemAudioMonitor")
            return
        }

        logDebug("正在启动系统音频监控...", module: "SystemAudioMonitor")

        // 监听 Now Playing 信息变化
        setupNowPlayingNotifications()

        // 启动定时器定期检查(备用方案)
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkPlaybackStatus()
        }

        isMonitoring = true
        logSuccess("系统音频监控已启动", module: "SystemAudioMonitor")

        // 立即检查一次
        checkPlaybackStatus()
    }

    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止系统音频监控...", module: "SystemAudioMonitor")

        // 移除通知监听
        NotificationCenter.default.removeObserver(self)

        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false

        logSuccess("系统音频监控已停止", module: "SystemAudioMonitor")
    }

    // MARK: - Private Methods

    private func setupNowPlayingNotifications() {
        // 监听 Now Playing 信息变化
        // 注意:这个通知可能不是所有应用都会发送
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingInfoDidChange),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil
        )

        // 监听播放状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingInfoDidChange),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil
        )
    }

    @objc private func nowPlayingInfoDidChange(_ notification: Notification) {
        logDebug("Now Playing 信息发生变化", module: "SystemAudioMonitor")
        checkPlaybackStatus()
    }

    private func checkPlaybackStatus() {
        // 获取所有可能正在播放的应用
        let allPlayingApps = getAllPlayingApplications()

        // 过滤掉网易云音乐
        let otherApps = allPlayingApps.filter { appName in
            !appName.contains("NeteaseMusic") &&
            !appName.contains("网易云音乐") &&
            !appName.contains("NetEase")
        }

        let hasOtherAppPlaying = !otherApps.isEmpty

        // 如果状态发生变化,触发回调
        if hasOtherAppPlaying != isOtherAppPlaying {
            isOtherAppPlaying = hasOtherAppPlaying

            if hasOtherAppPlaying {
                logInfo("检测到其他应用正在播放: \(otherApps.joined(separator: ", "))", module: "SystemAudioMonitor")
            } else {
                logInfo("其他应用停止播放", module: "SystemAudioMonitor")
            }

            DispatchQueue.main.async { [weak self] in
                self?.onOtherAppPlayingChanged?(hasOtherAppPlaying)
            }
        } else if hasOtherAppPlaying && !otherApps.isEmpty {
            // 状态未变化,但定期输出调试信息
            logDebug("其他应用持续播放中: \(otherApps.joined(separator: ", "))", module: "SystemAudioMonitor")
        }
    }

    /// 获取所有正在播放的应用(包括网易云)
    private func getAllPlayingApplications() -> [String] {
        var playingApps: [String] = []

        // 方案1: 检查 MPNowPlayingInfoCenter
        // 注意:这个方法只能获取当前"主要"的播放应用(通常是最后一个开始播放的)
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        if let info = nowPlayingInfo,
           let title = info[MPMediaItemPropertyTitle] as? String {
            logDebug("Now Playing Info: \(title)", module: "SystemAudioMonitor")
            // 但我们无法从 Now Playing Info 获取应用名称
            // 所以这个方法用处不大
        }

        // 方案2: 检查所有活跃的媒体应用(主要方法)
        let activeMediaApps = getActiveMediaApplications()
        playingApps.append(contentsOf: activeMediaApps)

        return playingApps
    }

    /// 获取所有活跃的媒体应用
    private func getActiveMediaApplications() -> [String] {
        var activeApps: [String] = []
        let runningApps = NSWorkspace.shared.runningApplications

        // 常见媒体应用的 Bundle ID
        // 注意:不包括浏览器,因为浏览器即使在前台也不一定在播放音频
        let mediaAppBundleIDs: [String: String] = [
            "com.apple.Music": "Apple Music",
            "com.spotify.client": "Spotify",
            // "com.apple.Safari": "Safari",  // 移除浏览器
            // "com.google.Chrome": "Chrome",
            // "org.mozilla.firefox": "Firefox",
            // "com.microsoft.edgemac": "Edge",
            "com.colliderli.iina": "IINA",
            "org.videolan.vlc": "VLC",
            "com.apple.QuickTimePlayerX": "QuickTime",
            "com.netease.163music": "NeteaseMusic"  // 也检测网易云,稍后过滤
        ]

        // 对于专门的媒体应用(Music, Spotify, 视频播放器)
        // 只要它们在运行且未隐藏,就认为可能在播放
        for app in runningApps where !app.isHidden {
            if let bundleID = app.bundleIdentifier,
               let appName = mediaAppBundleIDs[bundleID] {
                activeApps.append(appName)
                logDebug("检测到媒体应用运行中: \(appName)", module: "SystemAudioMonitor")
            }
        }

        return activeApps
    }
}
