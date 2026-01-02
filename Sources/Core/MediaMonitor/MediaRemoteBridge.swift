//
//  MediaRemoteBridge.swift
//  StillMusicWhenBack
//
//  MediaRemote 私有框架桥接
//  用于触发 NowPlaying 应用刷新
//

import Foundation

// MARK: - MediaRemote 私有 API 声明

/// 设置覆盖的 NowPlaying 应用
@_silgen_name("MRMediaRemoteSetOverriddenNowPlayingApplication")
func MRMediaRemoteSetOverriddenNowPlayingApplication(_ bundleID: CFString?) -> Void

/// 启用/禁用 NowPlaying 应用覆盖
@_silgen_name("MRMediaRemoteSetNowPlayingApplicationOverrideEnabled")
func MRMediaRemoteSetNowPlayingApplicationOverrideEnabled(_ enabled: Bool) -> Void

// MARK: - MediaRemoteBridge

class MediaRemoteBridge {

    // MARK: - NowPlaying 刷新

    /// 触发 NowPlaying 刷新到指定应用
    /// - Parameter bundleID: 目标应用的 bundleID
    static func triggerNowPlayingRefresh(toBundleID bundleID: String) {
        logInfo("触发 NowPlaying 刷新到: \(bundleID)", module: "MediaRemote")

        // 1. 启用 NowPlaying 应用覆盖
        MRMediaRemoteSetNowPlayingApplicationOverrideEnabled(true)

        // 2. 设置覆盖的 NowPlaying 应用
        MRMediaRemoteSetOverriddenNowPlayingApplication(bundleID as CFString)

        // 3. 短暂延迟后取消覆盖，让系统重新评估
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MRMediaRemoteSetOverriddenNowPlayingApplication(nil)
            MRMediaRemoteSetNowPlayingApplicationOverrideEnabled(false)
            logDebug("NowPlaying 覆盖已取消", module: "MediaRemote")
        }
    }

    // MARK: - 前台应用检测

    /// 获取当前前台应用的 bundleID
    /// - Returns: 前台应用的 bundleID，获取失败返回 nil
    static func getFrontmostAppBundleID() -> String? {
        let script = """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            return bundle identifier of frontApp
        end tell
        """

        return executeAppleScript(script)
    }

    // MARK: - AppleScript 执行

    /// 执行 AppleScript 并返回结果
    private static func executeAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            logError("创建 AppleScript 失败", module: "MediaRemote")
            return nil
        }

        let result = appleScript.executeAndReturnError(&error)

        if let error = error {
            logError("AppleScript 执行失败: \(error)", module: "MediaRemote")
            return nil
        }

        return result.stringValue
    }
}
