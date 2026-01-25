//
//  MediaMonitorProtocol.swift
//  StillMusicWhenBack
//
//  媒体监控协议 - 监控“是否有其他应用出声”状态变化
//

protocol MediaMonitorProtocol {
    /// 开始监控
    func startMonitoring()

    /// 停止监控
    func stopMonitoring()

    /// 当音频监控状态变化时的回调
    /// 返回是否检测到除网易云外的其他应用出声
    var onStatusChanged: ((AudioMonitorStatus) -> Void)? { get set }
}
