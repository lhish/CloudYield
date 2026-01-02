//
//  NowPlayingMonitor.swift
//  StillMusicWhenBack
//
//  使用 media-control CLI 工具获取系统 "正在播放" 信息
//  检测其他应用是否在播放音频
//
//  注意：macOS 15.4+ 限制了 MediaRemote API 的直接访问
//  需要使用 media-control (brew install ungive/media-control/media-control) 来获取信息
//

import Foundation

// MARK: - NowPlayingInfo 结构体

private struct NowPlayingInfo: Codable {
    let bundleIdentifier: String?
    let title: String?
    let artist: String?
    let album: String?
    let playing: Bool?
    let elapsedTime: Double?
    let duration: Double?
    let playbackRate: Double?
}

// MARK: - NowPlayingMonitor

class NowPlayingMonitor: MediaMonitorProtocol {
    // MARK: - Properties

    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    private var isMonitoring = false
    private var lastAppBundleID: String?
    private var lastIsPlaying = false
    private var isOtherAppPlaying = false

    // 用于检测播放是否停止
    private var stoppedSince: Date?
    private let stoppedThreshold: TimeInterval = 3.0  // 3秒不变化视为停止

    // 轮询定时器
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0  // 每秒检查一次

    // media-control 路径
    private let mediaControlPath: String

    // MARK: - Initialization

    init() {
        // 查找 media-control 路径
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/media-control") {
            mediaControlPath = "/opt/homebrew/bin/media-control"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/media-control") {
            mediaControlPath = "/usr/local/bin/media-control"
        } else {
            mediaControlPath = "media-control"  // 依赖 PATH
        }
        logInfo("media-control 路径: \(mediaControlPath)", module: "NowPlaying")
    }

    // MARK: - MediaMonitorProtocol

    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已在监控中", module: "NowPlaying")
            return
        }

        logInfo("启动 Now Playing 监控...", module: "NowPlaying")

        // 检查 media-control 是否可用
        if !checkMediaControlAvailable() {
            logError("media-control 不可用，请运行: brew install ungive/media-control/media-control", module: "NowPlaying")
            return
        }

        // 启动轮询定时器
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkNowPlayingStatus()
        }
        if let timer = pollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        isMonitoring = true

        // 立即检查一次当前状态
        logInfo("执行首次 Now Playing 检查...", module: "NowPlaying")
        checkNowPlayingStatus()

        logSuccess("Now Playing 监控已启动", module: "NowPlaying")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止 Now Playing 监控...", module: "NowPlaying")

        // 停止轮询定时器
        pollTimer?.invalidate()
        pollTimer = nil

        // 重置状态
        isMonitoring = false
        lastAppBundleID = nil
        lastIsPlaying = false
        stoppedSince = nil
        isOtherAppPlaying = false

        logSuccess("Now Playing 监控已停止", module: "NowPlaying")
    }

    // MARK: - Private Methods

    private func checkMediaControlAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mediaControlPath)
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func checkNowPlayingStatus() {
        // 在后台队列执行命令
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let info = self.fetchNowPlayingInfo()

            // 回到主线程处理结果
            DispatchQueue.main.async {
                self.processNowPlayingInfo(info)
            }
        }
    }

    private func fetchNowPlayingInfo() -> NowPlayingInfo? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: mediaControlPath)
        process.arguments = ["get"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // 检查是否返回 null
            if let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               jsonString == "null" {
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(NowPlayingInfo.self, from: data)
        } catch {
            logDebug("获取 Now Playing 信息失败: \(error)", module: "NowPlaying")
            return nil
        }
    }

    private func processNowPlayingInfo(_ info: NowPlayingInfo?) {
        let now = Date()

        guard let info = info, let bundleID = info.bundleIdentifier else {
            // 没有 Now Playing 信息
            handleNoNowPlayingInfo()
            return
        }

        let isPlaying = info.playing ?? false
        let title = info.title ?? ""
        let artist = info.artist ?? ""

        // 判断当前是否为网易云音乐
        let isNetease = isNeteaseMusicApp(bundleID)

        logInfo("Now Playing: \(bundleID) - \(title) by \(artist), playing=\(isPlaying)", module: "NowPlaying")

        // 情况1: 检测到其他应用正在播放
        if isPlaying && !isNetease {
            if !isOtherAppPlaying {
                logInfo("检测到其他应用开始播放: \(bundleID)", module: "NowPlaying")
                setOtherAppPlaying(true)
            }
            stoppedSince = nil
        }
        // 情况2: 其他应用停止播放或切换回网易云
        else if isOtherAppPlaying {
            if isNetease && isPlaying {
                logInfo("播放切换回网易云", module: "NowPlaying")
                setOtherAppPlaying(false)
                stoppedSince = nil
            } else if !isPlaying || isNetease {
                // 其他应用停止播放，开始计时
                if stoppedSince == nil {
                    stoppedSince = now
                    logInfo("其他应用停止播放，开始计时...", module: "NowPlaying")
                } else if now.timeIntervalSince(stoppedSince!) >= stoppedThreshold {
                    logInfo("其他应用已停止播放超过 \(stoppedThreshold) 秒", module: "NowPlaying")
                    setOtherAppPlaying(false)
                    stoppedSince = nil
                }
            }
        }

        // 更新状态
        lastAppBundleID = bundleID
        lastIsPlaying = isPlaying
    }

    private func handleNoNowPlayingInfo() {
        // 如果之前有其他应用在播放，现在没有 Now Playing 信息了
        if isOtherAppPlaying {
            if stoppedSince == nil {
                stoppedSince = Date()
                logInfo("Now Playing 信息消失，开始计时...", module: "NowPlaying")
            } else if Date().timeIntervalSince(stoppedSince!) >= stoppedThreshold {
                logInfo("Now Playing 信息消失超过 \(stoppedThreshold) 秒", module: "NowPlaying")
                setOtherAppPlaying(false)
                stoppedSince = nil
            }
        }

        lastAppBundleID = nil
        lastIsPlaying = false
    }

    private func setOtherAppPlaying(_ playing: Bool) {
        guard playing != isOtherAppPlaying else { return }

        isOtherAppPlaying = playing
        logInfo("状态变化: isOtherAppPlaying = \(playing)", module: "NowPlaying")

        DispatchQueue.main.async { [weak self] in
            self?.onOtherAppPlayingChanged?(playing)
        }
    }

    /// 判断是否为网易云音乐应用
    private func isNeteaseMusicApp(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }

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
