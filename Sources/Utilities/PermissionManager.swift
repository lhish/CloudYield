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
        // 方法1: 使用 CGPreflightScreenCaptureAccess
        let preflight = CGPreflightScreenCaptureAccess()

        // 方法2: 尝试实际捕获来验证（更可靠）
        // 如果 preflight 返回 true，直接返回
        if preflight {
            return true
        }

        // 如果 preflight 返回 false，可能是缓存问题，尝试实际检测
        // 通过尝试获取可共享内容来验证权限
        do {
            let semaphore = DispatchSemaphore(value: 0)
            var hasPermission = false

            Task {
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    hasPermission = true
                } catch {
                    hasPermission = false
                }
                semaphore.signal()
            }

            // 等待最多 2 秒
            _ = semaphore.wait(timeout: .now() + 2)
            return hasPermission
        }
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
