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

    /// 检查是否有屏幕录制权限
    func hasScreenRecordingPermission() -> Bool {
        // 直接使用 CGPreflightScreenCaptureAccess
        // 这个 API 会返回实时的权限状态，不会有缓存问题
        let hasPermission = CGPreflightScreenCaptureAccess()

        // 调试日志
        if hasPermission {
            print("[PermissionManager] 🔧 DEBUG CGPreflightScreenCaptureAccess 返回: true（有权限）")
        } else {
            print("[PermissionManager] 🔧 DEBUG CGPreflightScreenCaptureAccess 返回: false（无权限）")
        }

        return hasPermission
    }

    /// 请求屏幕录制权限
    func requestScreenRecordingPermission() {
        // 尝试访问屏幕捕获，这会触发系统权限请求
        let _ = CGRequestScreenCaptureAccess()
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
