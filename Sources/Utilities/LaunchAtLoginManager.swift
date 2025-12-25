//
//  LaunchAtLoginManager.swift
//  StillMusicWhenBack
//
//  开机自启动管理器 - 使用 ServiceManagement 框架
//

import Foundation
import ServiceManagement

class LaunchAtLoginManager {
    // MARK: - Properties

    private static let service = SMAppService.mainApp

    // MARK: - Public Methods

    /// 启用开机自启动
    static func enable() {
        do {
            if service.status == .enabled {
                print("[LaunchAtLogin] 已经启用开机自启动")
                return
            }

            try service.register()
            print("[LaunchAtLogin] ✅ 已启用开机自启动")

            // 保存到 UserDefaults
            UserDefaults.standard.set(true, forKey: "LaunchAtLoginEnabled")

        } catch {
            print("[LaunchAtLogin] ❌ 启用失败: \(error)")
        }
    }

    /// 禁用开机自启动
    static func disable() {
        do {
            if service.status != .enabled {
                print("[LaunchAtLogin] 开机自启动未启用")
                return
            }

            try service.unregister()
            print("[LaunchAtLogin] ✅ 已禁用开机自启动")

            // 保存到 UserDefaults
            UserDefaults.standard.set(false, forKey: "LaunchAtLoginEnabled")

        } catch {
            print("[LaunchAtLogin] ❌ 禁用失败: \(error)")
        }
    }

    /// 切换开机自启动状态
    static func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    /// 检查是否已启用
    static var isEnabled: Bool {
        return service.status == .enabled
    }

    /// 获取状态描述
    static var statusDescription: String {
        switch service.status {
        case .enabled:
            return "已启用"
        case .notRegistered:
            return "未注册"
        case .notFound:
            return "未找到"
        case .requiresApproval:
            return "需要用户批准"
        @unknown default:
            return "未知状态"
        }
    }
}
