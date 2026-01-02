//
//  NowPlayingMonitor.swift
//  StillMusicWhenBack
//
//  使用 media-control CLI 工具获取系统 "正在播放" 信息
//  判断是否有非网易云应用在播放
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

    var onNowPlayingChanged: ((NowPlayingStatus) -> Void)?

    private var isMonitoring = false
    private var lastStatus: NowPlayingStatus?

    // 轮询定时器
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 0.1  // 每0.1秒检查一次

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
            logError("监控启动失败", module: "NowPlaying")
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
        lastStatus = nil

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

            let status = self.fetchNowPlayingStatus()

            // 回到主线程处理结果
            DispatchQueue.main.async {
                self.processStatus(status)
            }
        }
    }

    /// 获取 NowPlaying 状态
    /// - Returns: NowPlayingStatus，表示是否有非网易云应用在播放
    private func fetchNowPlayingStatus() -> NowPlayingStatus {
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

            // 检查是否返回 null（没有任何 NowPlaying）
            if let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               jsonString == "null" {
                // 没有任何应用在 NowPlaying，视为没有其他应用播放
                return NowPlayingStatus(isNeteaseAsNowPlaying: false, isOtherAppPlaying: false)
            }

            let decoder = JSONDecoder()
            let info = try decoder.decode(NowPlayingInfo.self, from: data)

            return processNowPlayingInfo(info)
        } catch {
            logDebug("获取 Now Playing 信息失败: \(error)", module: "NowPlaying")
            // 出错时视为没有其他应用播放
            return NowPlayingStatus(isNeteaseAsNowPlaying: false, isOtherAppPlaying: false)
        }
    }

    /// 处理 NowPlaying 信息，判断是否有非网易云应用在播放
    private func processNowPlayingInfo(_ info: NowPlayingInfo) -> NowPlayingStatus {
        guard let bundleID = info.bundleIdentifier else {
            // 没有 bundleID，视为没有应用播放
            return NowPlayingStatus(isNeteaseAsNowPlaying: false, isOtherAppPlaying: false)
        }

        let isPlaying = info.playing ?? false
        let isNetease = isNeteaseMusicApp(bundleID)

        let title = info.title ?? ""
        let artist = info.artist ?? ""

        // 判断状态
        let isNeteaseAsNowPlaying = isNetease
        let isOtherAppPlaying = isPlaying && !isNetease

        logDebug("NowPlaying: \(bundleID) - \(title) by \(artist), playing=\(isPlaying), isNetease=\(isNetease)", module: "NowPlaying")

        return NowPlayingStatus(isNeteaseAsNowPlaying: isNeteaseAsNowPlaying, isOtherAppPlaying: isOtherAppPlaying)
    }

    /// 处理状态变化
    private func processStatus(_ status: NowPlayingStatus) {
        // 检查状态是否变化
        if let lastStatus = lastStatus, lastStatus == status {
            // 状态未变化，不触发回调
            return
        }

        // 状态变化，更新并触发回调
        lastStatus = status

        if status.isOtherAppPlaying {
            logInfo("检测到其他应用开始播放", module: "NowPlaying")
        } else if status.isNeteaseAsNowPlaying {
            logInfo("NowPlaying 切换到网易云", module: "NowPlaying")
        } else {
            logInfo("其他应用停止播放", module: "NowPlaying")
        }

        onNowPlayingChanged?(status)
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
