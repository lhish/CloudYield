//
//  MonitorState.swift
//  StillMusicWhenBack
//
//  应用状态枚举 - 基于“其他应用是否出声”+“网易云是否播放”
//
//  状态由两个维度决定：
//  1. 是否检测到除网易云外的其他应用出声（Process Tap）
//  2. 网易云自身是否在播放（AppleScript检测）
//

import Foundation

// MARK: - 音频监控状态结构

/// 音频监控返回的状态信息
struct AudioMonitorStatus: Equatable {
    let isOtherAppAudible: Bool  // 是否检测到除网易云外的其他应用出声

    static let idle = AudioMonitorStatus(isOtherAppAudible: false)
}

// MARK: - 应用状态枚举

/// 状态模型
/// - otherPlayingNeteasePlaying: 其他应用出声 + 网易云播放（冲突，需自动暂停）
/// - otherPlayingNeteasePaused: 其他应用出声 + 网易云暂停
/// - neteasePlaying: 其他应用静音/停止出声 + 网易云播放
/// - neteasePaused: 其他应用静音/停止出声 + 网易云暂停
enum AppState: Equatable {
    case otherPlayingNeteasePlaying
    case otherPlayingNeteasePaused
    case neteasePlaying
    case neteasePaused

    var description: String {
        switch self {
        case .otherPlayingNeteasePlaying:
            return "检测到其他声音..."
        case .otherPlayingNeteasePaused:
            return "已暂停网易云"
        case .neteasePlaying:
            return "网易云播放中"
        case .neteasePaused:
            return "网易云已暂停"
        }
    }

    var icon: String {
        switch self {
        case .neteasePlaying:
            return "🎵"
        case .neteasePaused:
            return "⏸"
        case .otherPlayingNeteasePlaying:
            return "🔊"
        case .otherPlayingNeteasePaused:
            return "⏸"
        }
    }

    /// 是否有其他应用在播放
    var isOtherAppPlaying: Bool {
        switch self {
        case .otherPlayingNeteasePlaying, .otherPlayingNeteasePaused:
            return true
        default:
            return false
        }
    }

    /// 网易云是否在播放
    var isNeteasePlaying: Bool {
        switch self {
        case .neteasePlaying, .otherPlayingNeteasePlaying:
            return true
        default:
            return false
        }
    }

    /// 根据两个维度计算当前状态
    /// - Parameters:
    ///   - isOtherAppAudible: 是否检测到除网易云外的其他应用出声
    ///   - isNeteasePlaying: 网易云是否在播放（AppleScript 检测）
    static func from(
        isOtherAppAudible: Bool,
        isNeteasePlaying: Bool
    ) -> AppState {
        if isOtherAppAudible {
            return isNeteasePlaying ? .otherPlayingNeteasePlaying : .otherPlayingNeteasePaused
        } else {
            return isNeteasePlaying ? .neteasePlaying : .neteasePaused
        }
    }
}
