import Foundation
import CoreAudio
import AVFAudio

/// 实时音频监控器 - 通过监听音频设备的实际输出来检测是否有声音
class RealTimeAudioMonitor: MediaMonitorProtocol {
    var onOtherAppPlayingChanged: ((Bool) -> Void)?

    private var audioDeviceID: AudioDeviceID?
    private var ioProcID: AudioDeviceIOProcID?
    private var monitorTimer: Timer?
    private var isOtherAppPlaying = false

    // 音量检测参数
    private let volumeThreshold: Float = 0.01  // 音量阈值
    private let checkInterval: TimeInterval = 0.5
    private var recentVolumeSamples: [Float] = []
    private let maxSamples = 10

    init() {
        logInfo("实时音频监控器初始化", module: "RealTimeAudio")
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        logInfo("启动实时音频监控...", module: "RealTimeAudio")

        // 获取默认输出设备
        guard let deviceID = getDefaultOutputDevice() else {
            logError("无法获取默认音频输出设备", module: "RealTimeAudio")
            return
        }

        audioDeviceID = deviceID
        logInfo("获取到音频设备 ID: \(deviceID)", module: "RealTimeAudio")

        // 安装音频 IO Proc 来监听实际的音频输出
        let status = AudioDeviceCreateIOProcID(
            deviceID,
            audioIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &ioProcID
        )

        if status != noErr {
            logError("无法创建 IOProc: \(status)", module: "RealTimeAudio")
            return
        }

        // 启动 IO Proc
        if let ioProcID = ioProcID {
            let startStatus = AudioDeviceStart(deviceID, ioProcID)
            if startStatus == noErr {
                logSuccess("IOProc 已启动", module: "RealTimeAudio")
            } else {
                logError("无法启动 IOProc: \(startStatus)", module: "RealTimeAudio")
            }
        }

        // 启动定时器来处理检测结果
        monitorTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkVolumeLevel()
        }
    }

    func stopMonitoring() {
        logInfo("停止实时音频监控", module: "RealTimeAudio")

        monitorTimer?.invalidate()
        monitorTimer = nil

        if let deviceID = audioDeviceID, let ioProcID = ioProcID {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        }

        audioDeviceID = nil
        ioProcID = nil
    }

    /// 获取默认输出设备
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    /// 检查音量级别
    private func checkVolumeLevel() {
        // 计算最近采样的平均音量
        guard !recentVolumeSamples.isEmpty else {
            updatePlayingState(false)
            return
        }

        let avgVolume = recentVolumeSamples.reduce(0.0, +) / Float(recentVolumeSamples.count)
        let hasSound = avgVolume > volumeThreshold

        logDebug("平均音量: \(String(format: "%.4f", avgVolume)), 阈值: \(volumeThreshold), 有声音: \(hasSound)", module: "RealTimeAudio")

        // 检查是否是网易云音乐在播放
        if hasSound && isNeteaseMusicPlaying() {
            logInfo("检测到网易云音乐正在播放，忽略", module: "RealTimeAudio")
            updatePlayingState(false)
        } else {
            updatePlayingState(hasSound)
        }
    }

    /// 更新播放状态
    private func updatePlayingState(_ isPlaying: Bool) {
        if isOtherAppPlaying != isPlaying {
            isOtherAppPlaying = isPlaying
            logInfo("其他应用播放状态变化: \(isPlaying)", module: "RealTimeAudio")
            onOtherAppPlayingChanged?(isPlaying)
        }
    }

    /// 检查网易云音乐是否在播放
    private func isNeteaseMusicPlaying() -> Bool {
        let script = """
        tell application "System Events"
            if exists (process "NeteaseMusic") then
                tell process "NeteaseMusic"
                    try
                        set menuItemName to name of menu item 1 of menu "控制" of menu bar item "控制" of menu bar 1
                        if menuItemName is "暂停" then
                            return true
                        else
                            return false
                        end if
                    on error
                        return false
                    end try
                end tell
            else
                return false
            end if
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.booleanValue
            }
        }

        return false
    }

    /// 添加音量采样
    fileprivate func addVolumeSample(_ volume: Float) {
        recentVolumeSamples.append(volume)
        if recentVolumeSamples.count > maxSamples {
            recentVolumeSamples.removeFirst()
        }
    }
}

/// Audio IO Proc 回调函数
private func audioIOProc(
    inDevice: AudioDeviceID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {

    guard let clientData = inClientData else {
        return noErr
    }

    let monitor = Unmanaged<RealTimeAudioMonitor>.fromOpaque(clientData).takeUnretainedValue()

    // 分析输出缓冲区的音频数据
    let bufferList = outOutputData.pointee
    let buffers = UnsafeBufferPointer<AudioBuffer>(
        start: &outOutputData.pointee.mBuffers,
        count: Int(bufferList.mNumberBuffers)
    )

    var totalRMS: Float = 0
    var sampleCount = 0

    for buffer in buffers {
        guard let data = buffer.mData else { continue }

        let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let samples = data.assumingMemoryBound(to: Float.self)

        // 计算 RMS (均方根)
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = samples[i]
            sum += sample * sample
        }

        totalRMS += sum
        sampleCount += frameCount
    }

    if sampleCount > 0 {
        let rms = sqrt(totalRMS / Float(sampleCount))
        monitor.addVolumeSample(rms)
    }

    return noErr
}
