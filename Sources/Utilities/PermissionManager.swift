//
//  PermissionManager.swift
//  StillMusicWhenBack
//
//  权限管理器 - 检查和请求系统权限
//

import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit

class PermissionManager {
    // MARK: - Screen Recording Permission

    /// 检查是否有屏幕录制权限（仅检查，不会触发请求）
    func hasScreenRecordingPermission() -> Bool {
        let result = CGPreflightScreenCaptureAccess()
        print("🔍 [PermissionManager] CGPreflightScreenCaptureAccess() 返回: \(result)")

        // 额外验证：检查TCC数据库
        let task = Process()
        task.launchPath = "/usr/bin/sqlite3"
        task.arguments = [
            "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db",
            "SELECT service, allowed FROM access WHERE service = 'kTCCServiceScreenCapture';"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("🔍 [PermissionManager] TCC数据库查询结果: \(output)")
            }
        } catch {
            print("⚠️ [PermissionManager] TCC数据库查询失败: \(error)")
        }

        return result
    }

    /// 请求屏幕录制权限（会弹出系统权限对话框）
    func requestScreenRecordingPermission() {
        // CGRequestScreenCaptureAccess 会触发系统权限请求对话框
        // 这个函数只调用一次！
        CGRequestScreenCaptureAccess()
    }

    /// 打开屏幕录制权限设置
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility Permission

    /// 检查是否有辅助功能权限
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        // 创建权限请求选项
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 打开辅助功能权限设置
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Combined Permission Check

    /// 检查所有必要权限
    func checkAllPermissions() -> (screenRecording: Bool, accessibility: Bool) {
        let screenRecording = hasScreenRecordingPermission()
        let accessibility = hasAccessibilityPermission()

        print("[Permissions] 屏幕录制权限: \(screenRecording ? "✅" : "❌")")
        print("[Permissions] 辅助功能权限: \(accessibility ? "✅" : "❌")")

        return (screenRecording, accessibility)
    }

    /// 显示权限请求提示
    func showPermissionGuide() {
        let (screenRecording, accessibility) = checkAllPermissions()

        if !screenRecording || !accessibility {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要系统权限"

                var message = "为了正常工作，StillMusicWhenBack 需要以下权限：\n\n"

                if !screenRecording {
                    message += "✗ 屏幕录制权限（用于监控系统音频）\n"
                }

                if !accessibility {
                    message += "✗ 辅助功能权限（用于控制网易云音乐）\n"
                }

                message += "\n请在系统设置中授予这些权限，然后重启应用。"

                alert.informativeText = message
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if !screenRecording {
                        self.openScreenRecordingSettings()
                    } else if !accessibility {
                        self.openAccessibilitySettings()
                    }
                }
            }
        }
    }
}
