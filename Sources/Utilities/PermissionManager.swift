//
//  PermissionManager.swift
//  StillMusicWhenBack
//
//  权限管理器 - 检查和请求系统权限
//

import Foundation
import AppKit
import ApplicationServices

class PermissionManager {
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
}
