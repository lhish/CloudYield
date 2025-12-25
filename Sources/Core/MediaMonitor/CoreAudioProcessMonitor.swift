//
//  CoreAudioProcessMonitor.swift
//  StillMusicWhenBack
//
//  使用 Core Audio API 检测哪些进程正在使用音频设备
//  类似 Windows 音量混合器的功能
//

import Foundation
import CoreAudio
import AudioToolbox
import AppKit

class CoreAudioProcessMonitor: MediaMonitorProtocol {
    // MARK: - Properties

    private var monitorTimer: Timer?
    private var isMonitoring = false
    private let checkInterval: TimeInterval = 0.5

    private var isOtherAppPlaying = false
    private var lastPlayingProcesses: Set<pid_t> = []

    // 回调
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "CoreAudioProcess")
            return
        }

        logDebug("正在启动 Core Audio 进程监控...", module: "CoreAudioProcess")

        // 启动定时器
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkAudioProcesses()
        }

        isMonitoring = true
        logSuccess("Core Audio 进程监控已启动", module: "CoreAudioProcess")

        // 立即检查一次
        checkAudioProcesses()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止 Core Audio 进程监控...", module: "CoreAudioProcess")

        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false

        logSuccess("Core Audio 进程监控已停止", module: "CoreAudioProcess")
    }

    // MARK: - Private Methods

    private func checkAudioProcesses() {
        // 获取默认输出设备
        guard let deviceID = getDefaultOutputDevice() else {
            return
        }

        // 获取正在使用该设备的进程
        let processes = getProcessesUsingDevice(deviceID)

        // 将进程 ID 转换为应用名称
        var playingApps: [String] = []
        var otherProcessIDs: Set<pid_t> = []

        for pid in processes {
            if let appName = getApplicationName(for: pid) {
                // 过滤掉网易云音乐和系统服务
                if !appName.contains("NeteaseMusic") &&
                   !appName.contains("网易云音乐") &&
                   !appName.contains("NetEase") &&
                   !appName.contains("coreaudiod") &&
                   !appName.contains("StillMusicWhenBack") &&
                   !appName.contains("VisualizerService") &&  // Apple Music 可视化服务
                   !appName.contains("音乐") &&                // 系统音乐服务
                   !appName.localizedCaseInsensitiveContains("music") {  // 其他音乐相关系统服务
                    playingApps.append(appName)
                    otherProcessIDs.insert(pid)
                }
            }
        }

        let hasOtherAppPlaying = !otherProcessIDs.isEmpty

        // 检测变化
        if otherProcessIDs != lastPlayingProcesses {
            lastPlayingProcesses = otherProcessIDs

            if !playingApps.isEmpty {
                logInfo("检测到应用正在使用音频: \(playingApps.joined(separator: ", "))", module: "CoreAudioProcess")
            } else {
                logDebug("没有其他应用使用音频", module: "CoreAudioProcess")
            }
        }

        // 状态变化回调
        if hasOtherAppPlaying != isOtherAppPlaying {
            isOtherAppPlaying = hasOtherAppPlaying

            if hasOtherAppPlaying {
                logInfo("其他应用开始使用音频", module: "CoreAudioProcess")
            } else {
                logInfo("其他应用停止使用音频", module: "CoreAudioProcess")
            }

            DispatchQueue.main.async { [weak self] in
                self?.onOtherAppPlayingChanged?(hasOtherAppPlaying)
            }
        }
    }

    // MARK: - Core Audio Helper Methods

    /// 获取默认音频输出设备
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            logDebug("无法获取默认输出设备", module: "CoreAudioProcess")
            return nil
        }

        return deviceID
    }

    /// 获取正在使用指定设备的进程列表
    private func getProcessesUsingDevice(_ deviceID: AudioDeviceID) -> [pid_t] {
        var processes: [pid_t] = []

        // 方法1: 尝试获取 HOG mode 进程
        if let hogPID = getHogModeProcess(deviceID) {
            processes.append(hogPID)
        }

        // 方法2: 检查所有运行中的媒体应用
        // 因为 macOS 不直接暴露"每个进程的音频使用情况" API
        // 我们需要结合启发式方法
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            // 跳过系统进程
            guard let bundleID = app.bundleIdentifier,
                  !bundleID.contains("apple.systemuiserver"),
                  !bundleID.contains("apple.Finder") else {
                continue
            }

            // 检查应用是否有音频会话
            if hasAudioSession(app.processIdentifier) {
                processes.append(app.processIdentifier)
            }
        }

        return processes
    }

    /// 获取独占设备的进程(HOG mode)
    private func getHogModeProcess(_ deviceID: AudioDeviceID) -> pid_t? {
        var hogPID: pid_t = -1
        var propertySize = UInt32(MemoryLayout<pid_t>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &hogPID
        )

        if status == noErr && hogPID > 0 {
            return hogPID
        }

        return nil
    }

    /// 检查进程是否有活跃的音频会话
    /// 这是一个启发式方法,基于进程类型判断
    private func hasAudioSession(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else {
            return false
        }

        // 常见媒体应用
        let mediaAppPrefixes = [
            "com.apple.Music",
            "com.spotify.client",
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.colliderli.iina",
            "org.videolan.vlc",
            "com.apple.QuickTimePlayerX",
            "com.netease.163music",
            "com.tencent.QQMusicMac"
        ]

        // 检查是否是媒体应用
        for prefix in mediaAppPrefixes {
            if bundleID.hasPrefix(prefix) {
                // 进一步检查:应用必须是活跃的或者在播放
                return app.isActive || !app.isHidden
            }
        }

        return false
    }

    /// 根据进程 ID 获取应用名称
    private func getApplicationName(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        return app.localizedName ?? app.bundleIdentifier
    }
}
