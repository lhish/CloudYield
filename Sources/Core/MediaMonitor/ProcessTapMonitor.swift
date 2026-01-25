//
//  ProcessTapMonitor.swift
//  CloudYield
//
//  使用 CoreAudio Process Tap 检测“除网易云外是否有其他应用正在出声”。
//  - macOS 14.2+ 才提供 Process Tap API
//  - 首次启用会触发「音频捕获（Audio Capture）」权限弹窗（需 Info.plist 配置 NSAudioCaptureUsageDescription）
//

import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class ProcessTapMonitor {
    struct Config {
        var evaluationInterval: TimeInterval = 0.1
        var dbOn: Double = -55
        var dbOff: Double = -65
        var minOnSeconds: TimeInterval = 0.05
        var minOffSeconds: TimeInterval = 0.10
        var staleTimeoutSeconds: TimeInterval = 0.35
        var excludeBundleIDSubstrings: [String] = ["netease", "163music"]
    }

    enum MonitorError: LocalizedError {
        case coreAudio(OSStatus, String)
        case missingDefaultOutputDevice

        var errorDescription: String? {
            switch self {
            case .coreAudio(let status, let message):
                return "\(message) (OSStatus=\(status))"
            case .missingDefaultOutputDevice:
                return "Failed to resolve the default output device."
            }
        }
    }

    var onAudibilityChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let config: Config

    private var isRunning = false
    private var restartWorkItem: DispatchWorkItem?

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapASBD: AudioStreamBasicDescription?

    private let sharedState = SharedState()
    private let ioQueue = DispatchQueue(label: "CloudYield.ProcessTapMonitor.IO", qos: .userInitiated)
    private let evalQueue = DispatchQueue(label: "CloudYield.ProcessTapMonitor.Eval", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    private var audible = false
    private var pendingTarget: Bool?
    private var pendingSince: Date?

    private var processListListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    init(config: Config = Config()) {
        self.config = config
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        do {
            try startTap()
            installListeners()
            startTimer()
        } catch {
            handleError(error)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        restartWorkItem?.cancel()
        restartWorkItem = nil

        stopTimer()
        removeListeners()
        destroyTap()
    }

    // MARK: - Restart

    private func requestRestart(reason: String) {
        guard isRunning else { return }

        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.destroyTap()
            do {
                try self.startTap()
            } catch {
                self.handleError(error)
            }
        }
        restartWorkItem = item
        evalQueue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Core

    private func startTap() throws {
        let (excludedProcessIDs, _) = try findExcludedProcessObjectIDs()

        let outputDeviceID = try AudioObjectID.system.readDefaultOutputDevice()
        guard outputDeviceID.isValid else { throw MonitorError.missingDefaultOutputDevice }
        let outputUID = try outputDeviceID.readDeviceUID()

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcessIDs)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else { throw MonitorError.coreAudio(err, "AudioHardwareCreateProcessTap failed (\(fourCC(err)))") }
        processTapID = tapID

        tapASBD = try tapID.readAudioTapStreamBasicDescription()

        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CloudYield Process Tap",
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
        guard err == noErr else { throw MonitorError.coreAudio(err, "AudioHardwareCreateAggregateDevice failed (\(fourCC(err)))") }
        aggregateDeviceID = aggID

        guard let tapASBD else { throw MonitorError.coreAudio(-1, "Tap format unavailable") }
        var procID: AudioDeviceIOProcID?
        let ioBlock: AudioDeviceIOBlock = { [sharedState = self.sharedState, tapASBD] _, inInputData, _, _, _ in
            if let rms = computeRMS(bufferList: inInputData, asbd: tapASBD) {
                let db = 20.0 * log10(max(rms, 1e-9))
                sharedState.update(db: db)
            }
        }

        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue, ioBlock)
        guard err == noErr else { throw MonitorError.coreAudio(err, "AudioDeviceCreateIOProcIDWithBlock failed (\(fourCC(err)))") }
        deviceProcID = procID

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { throw MonitorError.coreAudio(err, "AudioDeviceStart failed (\(fourCC(err)))") }
    }

    private func destroyTap() {
        stopTimer()

        if aggregateDeviceID.isValid {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                self.deviceProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            processTapID = .unknown
        }

        tapASBD = nil
        audible = false
        pendingTarget = nil
        pendingSince = nil
    }

    // MARK: - Evaluation

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: evalQueue)
        timer.schedule(deadline: .now(), repeating: config.evaluationInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func stableDuration(for target: Bool) -> TimeInterval {
        target ? config.minOnSeconds : config.minOffSeconds
    }

    private func tick() {
        let now = Date()
        var (db, age) = sharedState.snapshot(now: now)
        if age >= config.staleTimeoutSeconds {
            db = -Double.infinity
        }

        let immediateTarget: Bool
        if audible {
            immediateTarget = db > config.dbOff
        } else {
            immediateTarget = db >= config.dbOn
        }

        if immediateTarget == audible {
            pendingTarget = nil
            pendingSince = nil
            return
        }

        if pendingTarget != immediateTarget {
            pendingTarget = immediateTarget
            pendingSince = now
            return
        }

        guard let since = pendingSince else { return }
        guard now.timeIntervalSince(since) >= stableDuration(for: immediateTarget) else { return }

        audible = immediateTarget
        pendingTarget = nil
        pendingSince = nil

        DispatchQueue.main.async { [weak self] in
            self?.onAudibilityChanged?(immediateTarget)
        }
    }

    // MARK: - Listeners

    private func installListeners() {
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let processListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.requestRestart(reason: "processListChanged")
        }
        self.processListListener = processListListener
        _ = AudioObjectAddPropertyListenerBlock(.system, &processListAddress, evalQueue, processListListener)

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultOutputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.requestRestart(reason: "defaultOutputChanged")
        }
        self.defaultOutputListener = defaultOutputListener
        _ = AudioObjectAddPropertyListenerBlock(.system, &defaultOutputAddress, evalQueue, defaultOutputListener)
    }

    private func removeListeners() {
        if let processListListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(.system, &address, evalQueue, processListListener)
            self.processListListener = nil
        }

        if let defaultOutputListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(.system, &address, evalQueue, defaultOutputListener)
            self.defaultOutputListener = nil
        }
    }

    // MARK: - Error

    private func handleError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    // MARK: - Helpers

    private func findExcludedProcessObjectIDs() throws -> ([AudioObjectID], [String]) {
        let substrings = config.excludeBundleIDSubstrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !substrings.isEmpty else {
            return ([], [])
        }

        let processObjectIDs = try getProcessObjectList()
        if processObjectIDs.isEmpty {
            return ([], [])
        }

        var excluded: [AudioObjectID] = []
        var matchedBundleIDs: Set<String> = []

        for objectID in processObjectIDs where objectID.isValid {
            do {
                let bundleID = try objectID.readProcessBundleID()
                let bundleLower = bundleID.lowercased()
                if substrings.contains(where: { bundleLower.contains($0.lowercased()) }) {
                    excluded.append(objectID)
                    matchedBundleIDs.insert(bundleID)
                }
            } catch {
                // Ignore unreadable process objects.
            }
        }

        return (excluded, Array(matchedBundleIDs).sorted())
    }
}

// MARK: - Shared State

@available(macOS 14.2, *)
private final class SharedState {
    private let lock = NSLock()
    private var lastCallbackTime = Date.distantPast
    private var latestDB: Double = -Double.infinity

    func update(db: Double) {
        lock.lock()
        lastCallbackTime = Date()
        latestDB = db
        lock.unlock()
    }

    func snapshot(now: Date) -> (db: Double, age: TimeInterval) {
        lock.lock()
        let db = latestDB
        let age = now.timeIntervalSince(lastCallbackTime)
        lock.unlock()
        return (db, age)
    }
}

// MARK: - CoreAudio Utilities

@available(macOS 14.2, *)
private extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isValid: Bool { self != .unknown }

    func readDefaultOutputDevice() throws -> AudioDeviceID {
        guard self == .system else { throw ProcessTapMonitor.MonitorError.coreAudio(-1, "System object required") }
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
            throw ProcessTapMonitor.MonitorError.coreAudio(err, "AudioObjectGetPropertyDataSize failed for selector \(address.mSelector)")
        }

        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, pointer)
        }
        guard err == noErr else {
            throw ProcessTapMonitor.MonitorError.coreAudio(err, "AudioObjectGetPropertyData failed for selector \(address.mSelector)")
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
        throw ProcessTapMonitor.MonitorError.coreAudio(status1, "Failed to get process object list size")
    }
    if dataSize == 0 {
        return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var objects = Array<AudioObjectID>(repeating: .unknown, count: count)
    var dataSizeCopy = dataSize
    let status2 = AudioObjectGetPropertyData(.system, &address, 0, nil, &dataSizeCopy, &objects)
    guard status2 == noErr else {
        throw ProcessTapMonitor.MonitorError.coreAudio(status2, "Failed to read process object list")
    }

    let finalCount = Int(dataSizeCopy) / MemoryLayout<AudioObjectID>.size
    return Array(objects.prefix(finalCount))
}

@available(macOS 14.2, *)
private func fourCC(_ status: OSStatus) -> String {
    let n = UInt32(bitPattern: status)
    let chars: [UInt8] = [
        UInt8((n >> 24) & 0xff),
        UInt8((n >> 16) & 0xff),
        UInt8((n >> 8) & 0xff),
        UInt8(n & 0xff)
    ]
    if chars.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
        return String(bytes: chars, encoding: .ascii) ?? "\(status)"
    }
    return "\(status)"
}

@available(macOS 14.2, *)
private func computeRMS(bufferList: UnsafePointer<AudioBufferList>, asbd: AudioStreamBasicDescription) -> Double? {
    guard asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

    let channels = Int(asbd.mChannelsPerFrame)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
    let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

    let bitsPerChannel = Int(asbd.mBitsPerChannel)
    let bytesPerFrame = Int(asbd.mBytesPerFrame)
    guard channels > 0, bitsPerChannel > 0, bytesPerFrame > 0 else { return nil }

    func normalizeInt(_ v: Double, maxAbs: Double) -> Double {
        if maxAbs == 0 { return 0 }
        return max(-1, min(1, v / maxAbs))
    }

    var sumSquares: Double = 0
    var count: Int = 0

    let bufferCount = Int(bufferList.pointee.mNumberBuffers)
    guard bufferCount > 0 else { return nil }

    let audioBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))

    if isNonInterleaved {
        for buf in audioBuffers {
            guard let data = buf.mData else { continue }
            let byteCount = Int(buf.mDataByteSize)
            if byteCount == 0 { continue }

            let frames = byteCount / bytesPerFrame
            if frames == 0 { continue }

            if isFloat, bitsPerChannel == 32 {
                let samples = data.bindMemory(to: Float.self, capacity: frames)
                for i in 0..<frames {
                    let s = Double(samples[i])
                    sumSquares += s * s
                    count += 1
                }
            } else if isFloat, bitsPerChannel == 64 {
                let samples = data.bindMemory(to: Double.self, capacity: frames)
                for i in 0..<frames {
                    let s = samples[i]
                    sumSquares += s * s
                    count += 1
                }
            } else if bitsPerChannel == 16 {
                let samples = data.bindMemory(to: Int16.self, capacity: frames)
                for i in 0..<frames {
                    let raw = isBigEndian ? Int16(bigEndian: samples[i]) : Int16(littleEndian: samples[i])
                    let s = normalizeInt(Double(raw), maxAbs: Double(Int16.max))
                    sumSquares += s * s
                    count += 1
                }
            } else if bitsPerChannel == 32 {
                let samples = data.bindMemory(to: Int32.self, capacity: frames)
                for i in 0..<frames {
                    let raw = isBigEndian ? Int32(bigEndian: samples[i]) : Int32(littleEndian: samples[i])
                    let s = normalizeInt(Double(raw), maxAbs: Double(Int32.max))
                    sumSquares += s * s
                    count += 1
                }
            } else {
                return nil
            }
        }
    } else {
        guard let buf = audioBuffers.first, let data = buf.mData else { return nil }
        let byteCount = Int(buf.mDataByteSize)
        if byteCount == 0 { return nil }

        let frames = byteCount / bytesPerFrame
        if frames == 0 { return nil }

        let bytesPerSample = bytesPerFrame / channels
        if bytesPerSample <= 0 { return nil }

        if isFloat, bitsPerChannel == 32, bytesPerSample == 4 {
            let samples = data.bindMemory(to: Float.self, capacity: frames * channels)
            for i in 0..<(frames * channels) {
                let s = Double(samples[i])
                sumSquares += s * s
                count += 1
            }
        } else if isFloat, bitsPerChannel == 64, bytesPerSample == 8 {
            let samples = data.bindMemory(to: Double.self, capacity: frames * channels)
            for i in 0..<(frames * channels) {
                let s = samples[i]
                sumSquares += s * s
                count += 1
            }
        } else if bitsPerChannel == 16, bytesPerSample == 2 {
            let samples = data.bindMemory(to: Int16.self, capacity: frames * channels)
            for i in 0..<(frames * channels) {
                let raw = isBigEndian ? Int16(bigEndian: samples[i]) : Int16(littleEndian: samples[i])
                let s = normalizeInt(Double(raw), maxAbs: Double(Int16.max))
                sumSquares += s * s
                count += 1
            }
        } else if bitsPerChannel == 32, bytesPerSample == 4 {
            let samples = data.bindMemory(to: Int32.self, capacity: frames * channels)
            for i in 0..<(frames * channels) {
                let raw = isBigEndian ? Int32(bigEndian: samples[i]) : Int32(littleEndian: samples[i])
                let s = normalizeInt(Double(raw), maxAbs: Double(Int32.max))
                sumSquares += s * s
                count += 1
            }
        } else {
            return nil
        }
    }

    guard count > 0 else { return nil }
    return sqrt(sumSquares / Double(count))
}

