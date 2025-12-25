//
//  MediaMonitorProtocol.swift
//  StillMusicWhenBack
//
//  媒体监控协议 - 统一不同监控实现的接口
//

import Foundation

protocol MediaMonitorProtocol {
    /// 开始监控
    func startMonitoring()

    /// 停止监控
    func stopMonitoring()

    /// 当检测到其他应用播放状态变化时的回调
    var onOtherAppPlayingChanged: ((Bool) -> Void)? { get set }
}
