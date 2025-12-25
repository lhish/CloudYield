//
//  MonitorState.swift
//  StillMusicWhenBack
//
//  监控状态枚举
//

import Foundation

enum MonitorState {
    case idle                   // 空闲状态
    case monitoring             // 正在监控
    case detectingOtherSound    // 检测到其他声音（计时中）
    case musicPaused            // 已暂停网易云音乐
    case waitingResume          // 等待恢复播放（计时中）
    case paused                 // 用户手动暂停监控

    var description: String {
        switch self {
        case .idle:
            return "空闲"
        case .monitoring:
            return "正在监控"
        case .detectingOtherSound:
            return "检测到声音..."
        case .musicPaused:
            return "已暂停音乐"
        case .waitingResume:
            return "等待恢复..."
        case .paused:
            return "监控已暂停"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "🎵"
        case .monitoring:
            return "✅"
        case .detectingOtherSound:
            return "🔊"
        case .musicPaused:
            return "⏸"
        case .waitingResume:
            return "⏳"
        case .paused:
            return "⏹"
        }
    }
}
