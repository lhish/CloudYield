//
//  NeteaseMusicController.swift
//  StillMusicWhenBack
//
//  网易云音乐控制器 - 通过 AppleScript 控制播放/暂停和检测状态
//

import Foundation
import AppKit

class NeteaseMusicController {
    // MARK: - Properties

    private let processName = "NeteaseMusic"
    private let menuBarItemName = "控制"
    private let playMenuItemName = "播放"
    private let pauseMenuItemName = "暂停"

    // 音量控制器（macOS 14.2+）
    private var volumeController: Any?

    private var isVolumeControlEnabled: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    @available(macOS 14.2, *)
    private func getVolumeController() -> NeteaseMusicVolumeController? {
        if volumeController == nil {
            let controller = NeteaseMusicVolumeController()
            controller.onError = { error in
                logWarning("音量控制器错误: \(error)", module: "MusicController")
            }
            volumeController = controller
        }
        return volumeController as? NeteaseMusicVolumeController
    }

    // MARK: - Initialization

    init() {
        // 启动音量控制器
        if #available(macOS 14.2, *), isVolumeControlEnabled {
            getVolumeController()?.start()
        }
    }

    deinit {
        // 停止音量控制器
        if #available(macOS 14.2, *), isVolumeControlEnabled {
            getVolumeController()?.stop()
        }
    }

    // MARK: - Public Methods

    /// 检查网易云音乐是否正在运行
    func isRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.localizedName == processName || $0.bundleIdentifier?.contains("netease") == true }
    }

    /// 检查网易云音乐是否正在播放（通过 AppleScript 检测菜单项）
    func isPlaying() -> Bool {
        guard isRunning() else {
            // 网易云未运行，不输出警告
            return false
        }

        // 通过检查菜单项来判断状态
        let script = """
        tell application "System Events"
            tell process "\(processName)"
                try
                    set menuItemName to name of menu item 1 of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1
                    return menuItemName
                on error
                    return "error"
                end try
            end tell
        end tell
        """

        let result = executeAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)

        if result == pauseMenuItemName {
            // 如果菜单显示"暂停"，说明正在播放
            return true
        } else if result == playMenuItemName {
            // 如果菜单显示"播放"，说明当前是暂停状态
            return false
        } else {
            // 只在第一次失败时警告，避免日志刷屏
            logDebug("AppleScript 获取播放状态返回: \(result)", module: "MusicController")
            return false
        }
    }

    /// 暂停播放（带音量淡出）
    @discardableResult
    func pause() -> Bool {
        guard isRunning() else {
            return false
        }

        // 如果支持音量控制，先淡出音量再暂停
        if #available(macOS 14.2, *), isVolumeControlEnabled, let controller = getVolumeController() {
            controller.fadeOut(duration: 0.5) { [weak self] in
                self?.pausePlayback()
            }
            return true
        }

        // 降级方案：直接暂停
        return pausePlayback()
    }

    /// 实际执行暂停操作
    @discardableResult
    private func pausePlayback() -> Bool {
        guard isRunning() else {
            return false
        }

        let script = """
        tell application "System Events"
            tell process "\(processName)"
                try
                    if exists menu item "\(pauseMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1 then
                        click menu item "\(pauseMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1
                        return "success"
                    else
                        return "not-playing"
                    end if
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        end tell
        """

        let result = executeAppleScript(script)

        if result.contains("success") {
            logSuccess("已暂停", module: "MusicController")
            return true
        }

        if result.contains("not-playing") {
            return false
        }

        logWarning("暂停失败: \(result)", module: "MusicController")
        return false
    }

    /// 恢复播放（带音量淡入）
    @discardableResult
    func play() -> Bool {
        guard isRunning() else {
            return false
        }

        // 先恢复播放
        guard playPlayback() else {
            return false
        }

        // 如果支持音量控制，淡入音量
        if #available(macOS 14.2, *), isVolumeControlEnabled, let controller = getVolumeController() {
            controller.fadeIn(duration: 0.5)
        }

        return true
    }

    /// 实际执行恢复播放操作
    @discardableResult
    private func playPlayback() -> Bool {
        guard isRunning() else {
            return false
        }

        let script = """
        tell application "System Events"
            tell process "\(processName)"
                try
                    if exists menu item "\(playMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1 then
                        click menu item "\(playMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1
                        return "success"
                    else
                        return "not-paused"
                    end if
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        end tell
        """

        let result = executeAppleScript(script)

        if result.contains("success") {
            logSuccess("已恢复播放", module: "MusicController")
            return true
        }

        if result.contains("not-paused") {
            return false
        }

        logWarning("恢复失败: \(result)", module: "MusicController")
        return false
    }

    // MARK: - Private Methods

    /// 执行 AppleScript（使用 NSAppleScript，避免频繁 spawn `osascript` 进程）
    private func executeAppleScript(_ script: String) -> String {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return "error: failed to create NSAppleScript"
        }

        let result = appleScript.executeAndReturnError(&error)
        if let error {
            logDebug("AppleScript 执行失败: \(error)", module: "MusicController")
            return "error: \(error)"
        }

        if let string = result.stringValue {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
