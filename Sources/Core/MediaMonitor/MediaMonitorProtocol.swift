//
//  MediaMonitorProtocol.swift
//  StillMusicWhenBack
//
//  媒体监控协议 - 监控 NowPlaying 状态变化
//

import Foundation

protocol MediaMonitorProtocol {
    /// 开始监控
    func startMonitoring()

    /// 停止监控
    func stopMonitoring()

    /// 当 NowPlaying 状态变化时的回调
    /// 返回是否有非网易云应用正在播放
    var onNowPlayingChanged: ((NowPlayingStatus) -> Void)? { get set }
}
