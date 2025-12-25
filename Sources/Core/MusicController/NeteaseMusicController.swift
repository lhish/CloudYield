//
//  NeteaseMusicController.swift
//  StillMusicWhenBack
//
//  网易云音乐控制器 - 通过 AppleScript 控制播放/暂停
//

import Foundation
import AppKit

class NeteaseMusicController {
    // MARK: - Properties

    private let processName = "NeteaseMusic"
    private let menuBarItemName = "控制"
    private let playMenuItemName = "播放"
    private let pauseMenuItemName = "暂停"

    // 缓存上一次的播放状态
    private var lastKnownState: PlaybackState = .unknown

    enum PlaybackState {
        case playing
        case paused
        case stopped
        case unknown
    }

    // MARK: - Public Methods

    /// 检查网易云音乐是否正在运行
    func isRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.localizedName == processName || $0.bundleIdentifier?.contains("netease") == true }
    }

    /// 检查网易云音乐是否正在播放
    func isPlaying() -> Bool {
        let state = getPlaybackState()
        lastKnownState = state
        return state == .playing
    }

    /// 暂停播放
    func pause() {
        guard isRunning() else {
            logWarning("网易云音乐未运行", module: "MusicController")
            return
        }

        logInfo("暂停播放...", module: "MusicController")

        // 方案1: 通过 AppleScript 点击菜单项
        let script = """
        tell application "System Events"
            tell process "\(processName)"
                try
                    click menu item "\(pauseMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1
                    return "success"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        end tell
        """

        let result = executeAppleScript(script)

        if result.contains("success") {
            logSuccess("已暂停", module: "MusicController")
            lastKnownState = .paused
        } else {
            logWarning("暂停失败，尝试备用方案...", module: "MusicController")
            // 备用方案：使用键盘快捷键
            pauseByKeyboard()
        }
    }

    /// 恢复播放
    func play() {
        guard isRunning() else {
            logWarning("网易云音乐未运行", module: "MusicController")
            return
        }

        logInfo("恢复播放...", module: "MusicController")

        let script = """
        tell application "System Events"
            tell process "\(processName)"
                try
                    click menu item "\(playMenuItemName)" of menu "\(menuBarItemName)" of menu bar item "\(menuBarItemName)" of menu bar 1
                    return "success"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        end tell
        """

        let result = executeAppleScript(script)

        if result.contains("success") {
            logSuccess("已恢复播放", module: "MusicController")
            lastKnownState = .playing
        } else {
            logWarning("恢复失败，尝试备用方案...", module: "MusicController")
            // 备用方案：使用键盘快捷键
            playByKeyboard()
        }
    }

    /// 获取上一次已知的播放状态
    func getLastKnownState() -> PlaybackState {
        return lastKnownState
    }

    // MARK: - Private Methods

    /// 获取当前播放状态
    private func getPlaybackState() -> PlaybackState {
        guard isRunning() else {
            return .stopped
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
            return .playing
        } else if result == playMenuItemName {
            // 如果菜单显示"播放"，说明当前是暂停状态
            return .paused
        } else {
            logWarning("无法获取播放状态: \(result)", module: "MusicController")
            return .unknown
        }
    }

    /// 执行 AppleScript
    private func executeAppleScript(_ script: String) -> String {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let output = appleScript?.executeAndReturnError(&error)

        if let error = error {
            logError("AppleScript 错误: \(error)", module: "MusicController")
            return "error: \(error)"
        }

        return output?.stringValue ?? ""
    }

    // MARK: - 备用方案：键盘快捷键

    /// 通过键盘快捷键暂停/播放（备用方案）
    private func pauseByKeyboard() {
        // 网易云音乐的播放/暂停快捷键通常是空格键
        // 需要先激活网易云窗口
        activateNeteaseMusic()

        // 等待一小段时间让窗口激活
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.simulateSpaceKey()
        }
    }

    private func playByKeyboard() {
        pauseByKeyboard() // 播放和暂停使用同一个快捷键
    }

    private func activateNeteaseMusic() {
        let script = """
        tell application "\(processName)"
            activate
        end tell
        """
        _ = executeAppleScript(script)
    }

    private func simulateSpaceKey() {
        // 创建空格键按下事件
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true) // 0x31 = 空格键
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false)

        // 发送事件
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        logInfo("已发送空格键事件", module: "MusicController")
    }
}
