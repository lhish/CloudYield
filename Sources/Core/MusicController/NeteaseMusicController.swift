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

    // MARK: - Public Methods

    /// 检查网易云音乐是否正在运行
    func isRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.localizedName == processName || $0.bundleIdentifier?.contains("netease") == true }
    }

    /// 检查网易云音乐是否正在播放（通过 AppleScript 检测菜单项）
    func isPlaying() -> Bool {
        guard isRunning() else {
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
            logWarning("AppleScript 无法获取播放状态: \(result)", module: "MusicController")
            return false
        }
    }

    /// 暂停播放
    func pause() {
        guard isRunning() else {
            logWarning("网易云音乐未运行", module: "MusicController")
            return
        }

        logInfo("暂停播放...", module: "MusicController")

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
        } else {
            logWarning("暂停失败: \(result)", module: "MusicController")
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
        } else {
            logWarning("恢复失败: \(result)", module: "MusicController")
        }
    }

    // MARK: - Private Methods

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
}
