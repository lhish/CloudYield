//
//  OtherAudioMonitor.swift
//  CloudYield
//
//  使用 CoreAudio Process Tap 检测“除网易云外是否有其他应用正在出声”。
//

import Foundation

@available(macOS 14.2, *)
final class OtherAudioMonitor: MediaMonitorProtocol {
    var onStatusChanged: ((AudioMonitorStatus) -> Void)?

    private var isMonitoring = false
    private var lastStatus: AudioMonitorStatus?

    private var processTapMonitor: ProcessTapMonitor?

    func startMonitoring() {
        guard !isMonitoring else {
            logInfo("已在监控中", module: "OtherAudio")
            return
        }

        let tapMonitor = ProcessTapMonitor()
        tapMonitor.onAudibilityChanged = { [weak self] audible in
            self?.processStatus(AudioMonitorStatus(isOtherAppAudible: audible))
        }
        tapMonitor.onError = { message in
            logError("Process Tap 启动/运行失败: \(message)", module: "OtherAudio")
        }

        processTapMonitor = tapMonitor
        tapMonitor.start()

        isMonitoring = true
        processStatus(.idle)

        logSuccess("其他应用出声监控已启动（Process Tap）", module: "OtherAudio")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止其他应用出声监控...", module: "OtherAudio")
        processTapMonitor?.stop()
        processTapMonitor = nil

        isMonitoring = false
        lastStatus = nil

        logSuccess("其他应用出声监控已停止", module: "OtherAudio")
    }

    private func processStatus(_ status: AudioMonitorStatus) {
        if let lastStatus, lastStatus == status {
            return
        }

        lastStatus = status

        if status.isOtherAppAudible {
            logInfo("检测到其他应用正在出声", module: "OtherAudio")
        } else {
            logInfo("其他应用已静音/停止出声", module: "OtherAudio")
        }

        onStatusChanged?(status)
    }
}

