//
//  NeteaseMusicVolumeController.swift
//  CloudYield
//
//  网易云音乐音量控制器 - 通过 Process Tap 实现音量淡入淡出
//

import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class NeteaseMusicVolumeController {

    // MARK: - Configuration

    struct Config {
        var fadeOutDuration: TimeInterval = 0.5
        var fadeInDuration: TimeInterval = 0.5
        var smoothingDuration: TimeInterval = 0.03  // 30ms 平滑过渡
    }

    // MARK: - Properties

    private let config: Config
    private let processName = "NeteaseMusic"

    // Process Tap 相关
    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapASBD: AudioStreamBasicDescription?

    // 音量状态（使用 nonisolated(unsafe) 以支持实时音频线程访问）
    private var _targetVolume: Float = 1.0
    private var _currentVolume: Float = 1.0
    private var _rampCoefficient: Float = 0.1

    // 队列
    private let ioQueue = DispatchQueue(label: "CloudYield.VolumeController.IO", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "CloudYield.VolumeController.Control", qos: .userInitiated)

    // 状态
    private var isActive = false
    private var fadeTimer: DispatchSourceTimer?

    // 回调
    var onError: ((String) -> Void)?

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 启动音量控制器
    func start() {
        guard !isActive else { return }

        do {
            try startProcessTap()
            isActive = true
            logSuccess("音量控制器已启动", module: "VolumeController")
        } catch {
            handleError(error)
        }
    }

    /// 停止音量控制器
    func stop() {
        guard isActive else { return }
        isActive = false

        stopFadeTimer()
        destroyProcessTap()

        logDebug("音量控制器已停止", module: "VolumeController")
    }

    /// 淡出音量
    func fadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        guard isActive else {
            completion()
            return
        }

        controlQueue.async { [weak self] in
            guard let self else { return }

            self._targetVolume = 0.0

            // 启动定时器监控淡出完成
            self.startFadeTimer(duration: duration) {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    /// 淡入音量
    func fadeIn(duration: TimeInterval) {
        guard isActive else { return }

        controlQueue.async { [weak self] in
            guard let self else { return }
            self._targetVolume = 1.0
        }
    }

    /// 立即设置音量
    func setVolume(_ volume: Float) {
        guard isActive else { return }

        controlQueue.async { [weak self] in
            guard let self else { return }
            self._targetVolume = max(0.0, min(1.0, volume))
            self._currentVolume = self._targetVolume
        }
    }

    // MARK: - Process Tap Management

    private func startProcessTap() throws {
        // 1. 查找网易云音乐的 AudioObjectID
        guard let neteaseObjectID = try findNeteaseProcessObjectID() else {
            throw VolumeControllerError.processNotFound
        }

        // 2. 获取默认输出设备
        let outputDeviceID = try AudioObjectID.system.readDefaultOutputDevice()
        guard outputDeviceID.isValid else {
            throw VolumeControllerError.noOutputDevice
        }
        let outputUID = try outputDeviceID.readDeviceUID()

        // 3. 创建 Process Tap（只针对网易云音乐）
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [neteaseObjectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped  // 原始音频静音，通过 Tap 输出

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioHardwareCreateProcessTap failed")
        }
        processTapID = tapID

        // 4. 获取 Tap 的音频格式
        tapASBD = try tapID.readAudioTapStreamBasicDescription()

        // 5. 创建 Aggregate Device
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CloudYield Volume Control",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var aggID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioHardwareCreateAggregateDevice failed")
        }
        aggregateDeviceID = aggID

        // 6. 计算平滑系数（基于采样率）
        if let asbd = tapASBD {
            let sampleRate = asbd.mSampleRate
            let smoothingFrames = config.smoothingDuration * sampleRate
            _rampCoefficient = Float(1.0 / smoothingFrames)
        }

        // 7. 创建 IO Proc
        guard let tapASBD else {
            throw VolumeControllerError.coreAudio(-1, "Tap format unavailable")
        }

        var procID: AudioDeviceIOProcID?
        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else { return }
            self.processAudio(inInputData, to: outOutputData)
        }

        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue, ioBlock)
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioDeviceCreateIOProcIDWithBlock failed")
        }
        deviceProcID = procID

        // 8. 启动设备
        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioDeviceStart failed")
        }
    }

    private func destroyProcessTap() {
        // 停止设备
        if aggregateDeviceID.isValid {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                self.deviceProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        // 销毁 Process Tap
        if processTapID.isValid {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            processTapID = .unknown
        }

        tapASBD = nil
    }

    // MARK: - Audio Processing

    private func processAudio(_ input: UnsafePointer<AudioBufferList>, to output: UnsafeMutablePointer<AudioBufferList>) {
        // 实时音频处理：必须遵守实时安全约束
        // - 不能分配内存
        // - 不能使用锁
        // - 只能使用原子操作和简单数学运算

        let targetVol = _targetVolume
        var currentVol = _currentVolume

        // 指数平滑：逐步接近目标音量
        currentVol += (targetVol - currentVol) * _rampCoefficient
        _currentVolume = currentVol

        // 处理音频缓冲区
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

        let bufferCount = min(Int(input.pointee.mNumberBuffers), Int(output.pointee.mNumberBuffers))

        for i in 0..<bufferCount {
            guard let inputData = inputBuffers[i].mData,
                  let outputData = outputBuffers[i].mData else {
                continue
            }

            let byteSize = min(inputBuffers[i].mDataByteSize, outputBuffers[i].mDataByteSize)
            guard byteSize > 0 else { continue }

            // 假设是 Float32 格式（Process Tap 默认格式）
            let sampleCount = Int(byteSize) / MemoryLayout<Float32>.size
            let inputSamples = inputData.bindMemory(to: Float32.self, capacity: sampleCount)
            let outputSamples = outputData.bindMemory(to: Float32.self, capacity: sampleCount)

            // 应用音量
            for j in 0..<sampleCount {
                outputSamples[j] = inputSamples[j] * currentVol
            }
        }
    }

    // MARK: - Fade Timer

    private func startFadeTimer(duration: TimeInterval, completion: @escaping () -> Void) {
        stopFadeTimer()

        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + duration)
        timer.setEventHandler { [weak self] in
            self?.stopFadeTimer()
            completion()
        }
        fadeTimer = timer
        timer.resume()
    }

    private func stopFadeTimer() {
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    // MARK: - Helper Methods

    private func findNeteaseProcessObjectID() throws -> AudioObjectID? {
        let processObjectIDs = try getProcessObjectList()

        for objectID in processObjectIDs where objectID.isValid {
            do {
                let bundleID = try objectID.readProcessBundleID()
                if bundleID.lowercased().contains("netease") || bundleID.lowercased().contains("163music") {
                    logDebug("找到网易云音乐进程: \(bundleID)", module: "VolumeController")
                    return objectID
                }
            } catch {
                // 忽略无法读取的进程
                continue
            }
        }

        return nil
    }

    private func handleError(_ error: Error) {
        let message: String
        if let vcError = error as? VolumeControllerError {
            message = vcError.localizedDescription
        } else {
            message = String(describing: error)
        }

        logError("音量控制器错误: \(message)", module: "VolumeController")

        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }
}

// MARK: - Error Types

@available(macOS 14.2, *)
enum VolumeControllerError: LocalizedError {
    case processNotFound
    case noOutputDevice
    case coreAudio(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .processNotFound:
            return "未找到网易云音乐进程"
        case .noOutputDevice:
            return "未找到默认输出设备"
        case .coreAudio(let status, let message):
            return "\(message) (OSStatus=\(status))"
        }
    }
}

// MARK: - CoreAudio Utilities

@available(macOS 14.2, *)
private extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isValid: Bool { self != .unknown }

    func readDefaultOutputDevice() throws -> AudioDeviceID {
        guard self == .system else {
            throw VolumeControllerError.coreAudio(-1, "System object required")
        }
        return try read(kAudioHardwarePropertyDefaultOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDeviceUID() throws -> String {
        return try readString(kAudioDevicePropertyDeviceUID)
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        return try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    func readProcessBundleID() throws -> String {
        return try readString(kAudioProcessPropertyBundleID)
    }

    private func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue)
    }

    private func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        let value: CFString = try read(
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
            defaultValue: "" as CFString
        )
        return value as String
    }

    private func read<T>(_ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        var address = address
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioObjectGetPropertyDataSize failed")
        }

        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, pointer)
        }
        guard err == noErr else {
            throw VolumeControllerError.coreAudio(err, "AudioObjectGetPropertyData failed")
        }

        return value
    }
}

@available(macOS 14.2, *)
private func getProcessObjectList() throws -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    let status1 = AudioObjectGetPropertyDataSize(.system, &address, 0, nil, &dataSize)
    guard status1 == noErr else {
        throw VolumeControllerError.coreAudio(status1, "Failed to get process object list size")
    }
    if dataSize == 0 {
        return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var objects = Array<AudioObjectID>(repeating: .unknown, count: count)
    var dataSizeCopy = dataSize
    let status2 = AudioObjectGetPropertyData(.system, &address, 0, nil, &dataSizeCopy, &objects)
    guard status2 == noErr else {
        throw VolumeControllerError.coreAudio(status2, "Failed to read process object list")
    }

    let finalCount = Int(dataSizeCopy) / MemoryLayout<AudioObjectID>.size
    return Array(objects.prefix(finalCount))
}
