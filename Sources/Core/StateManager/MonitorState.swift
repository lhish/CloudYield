//
//  MonitorState.swift
//  StillMusicWhenBack
//
//  应用状态枚举 - 6状态模型
//
//  状态由两个维度决定：
//  1. 是否有非网易云应用在播放（NowPlaying）
//  2. 网易云自身是否在播放（AppleScript检测）
//

import Foundation

// MARK: - NowPlaying 状态结构

/// NowPlaying 返回的状态信息
struct NowPlayingStatus: Equatable {
    let isNeteaseAsNowPlaying: Bool  // NowPlaying 是否为网易云
    let isOtherAppPlaying: Bool      // 是否有非网易云应用正在播放

    static let idle = NowPlayingStatus(isNeteaseAsNowPlaying: false, isOtherAppPlaying: false)
}

// MARK: - 应用状态枚举

/// 6状态模型
/// - S1: NowPlaying=网易云播放中
/// - S2: NowPlaying=网易云暂停
/// - S3: 其他应用播放 + 网易云播放（冲突状态，需自动暂停网易云）
/// - S4: 其他应用播放 + 网易云暂停
/// - S5: 其他应用暂停/无 + 网易云播放
/// - S6: 其他应用暂停/无 + 网易云暂停
enum AppState: Equatable {
    case s1_neteasePlayingAsNowPlaying    // 网易云是 NowPlaying 且播放中
    case s2_neteasePausedAsNowPlaying     // 网易云是 NowPlaying 且暂停
    case s3_otherPlayingNeteasePlaying    // 其他应用播放，网易云也在播放（冲突）
    case s4_otherPlayingNeteasePaused     // 其他应用播放，网易云已暂停
    case s5_otherIdleNeteasePlaying       // 其他应用空闲，网易云播放中
    case s6_otherIdleNeteasePaused        // 其他应用空闲，网易云暂停

    var description: String {
        switch self {
        case .s1_neteasePlayingAsNowPlaying:
            return "网易云播放中"
        case .s2_neteasePausedAsNowPlaying:
            return "网易云已暂停"
        case .s3_otherPlayingNeteasePlaying:
            return "检测到其他声音..."
        case .s4_otherPlayingNeteasePaused:
            return "已暂停网易云"
        case .s5_otherIdleNeteasePlaying:
            return "网易云播放中"
        case .s6_otherIdleNeteasePaused:
            return "网易云已暂停"
        }
    }

    var icon: String {
        switch self {
        case .s1_neteasePlayingAsNowPlaying:
            return "🎵"
        case .s2_neteasePausedAsNowPlaying:
            return "⏸"
        case .s3_otherPlayingNeteasePlaying:
            return "🔊"
        case .s4_otherPlayingNeteasePaused:
            return "⏸"
        case .s5_otherIdleNeteasePlaying:
            return "🎵"
        case .s6_otherIdleNeteasePaused:
            return "⏸"
        }
    }

    /// 是否有其他应用在播放
    var isOtherAppPlaying: Bool {
        switch self {
        case .s3_otherPlayingNeteasePlaying, .s4_otherPlayingNeteasePaused:
            return true
        default:
            return false
        }
    }

    /// 网易云是否在播放
    var isNeteasePlaying: Bool {
        switch self {
        case .s1_neteasePlayingAsNowPlaying, .s3_otherPlayingNeteasePlaying, .s5_otherIdleNeteasePlaying:
            return true
        default:
            return false
        }
    }

    /// 根据两个维度计算当前状态
    /// - Parameters:
    ///   - isOtherAppPlaying: 是否有非网易云应用正在播放
    ///   - isNeteasePlaying: 网易云是否在播放（AppleScript 检测）
    ///   - isNeteaseAsNowPlaying: NowPlaying 是否为网易云
    static func from(
        isOtherAppPlaying: Bool,
        isNeteasePlaying: Bool,
        isNeteaseAsNowPlaying: Bool
    ) -> AppState {
        if isNeteaseAsNowPlaying {
            // NowPlaying 是网易云
            return isNeteasePlaying ? .s1_neteasePlayingAsNowPlaying : .s2_neteasePausedAsNowPlaying
        } else if isOtherAppPlaying {
            // 有其他应用在播放
            return isNeteasePlaying ? .s3_otherPlayingNeteasePlaying : .s4_otherPlayingNeteasePaused
        } else {
            // 没有其他应用播放（或 NowPlaying 为空）
            return isNeteasePlaying ? .s5_otherIdleNeteasePlaying : .s6_otherIdleNeteasePaused
        }
    }
}

