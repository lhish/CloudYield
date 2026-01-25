import AudioToolbox
import CoreAudio
import Foundation

struct Config {
    var durationSeconds: TimeInterval = 10
    var printIntervalSeconds: TimeInterval = 0.2
    var dbOn: Double = -45
    var dbOff: Double = -55
    var minOnSeconds: TimeInterval = 0.15
    var minOffSeconds: TimeInterval = 0.25
    var staleTimeoutSeconds: TimeInterval = 0.35
    var outputPath: String?
    // Which output device to base the aggregate device on:
    // - output: default output device (most app audio)
    // - system: default system output device (sound effects)
    var outputDeviceKind: String = "output"

    var excludeBundleIDSubstrings: [String] = [
        "netease",
        "163music"
    ]
}

enum ProbeError: LocalizedError {
    case unsupportedOS
    case coreAudio(OSStatus, String)
    case missingDefaultOutputDevice

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Process Tap requires macOS 14.2+."
        case .coreAudio(let status, let message):
            return "\(message) (OSStatus=\(status))"
        case .missingDefaultOutputDevice:
            return "Failed to resolve the default output device."
        }
    }
}

func printUsageAndExit() -> Never {
    let usage = """
    Usage:
      swift scripts/process_tap_probe.swift [options]

    Options:
      --duration=N        Total run time in seconds (default: 10)
      --interval=N        Print interval in seconds (default: 0.2)
      --db-on=N           Switch to audible at/above this dBFS (default: -45)
      --db-off=N          Switch to silent at/below this dBFS (default: -55)
      --min-on=N          Min seconds to confirm audible (default: 0.15)
      --min-off=N         Min seconds to confirm silent (default: 0.25)
      --stale=N           Treat as silent if no audio callback for N seconds (default: 0.35)
      --out=PATH          Write JSONL output to PATH (instead of stdout)
      --device=KIND       Output device kind: output|system (default: output)
      --exclude=STR       Exclude bundle IDs containing STR (repeatable). Default excludes netease.
      --no-default-exclude Disable default excludes (netease/163music)
    Output:
      JSON lines to stdout:
        {"type":"event"|"status"|"start"|"error", ...}
    """
    fputs(usage + "\n", stderr)
    exit(2)
}

func parseArgs() -> Config {
    var config = Config()
    let args = Array(CommandLine.arguments.dropFirst())

    func popValue(_ prefix: String, _ arg: String) -> String? {
        if arg.hasPrefix(prefix + "=") {
            return String(arg.dropFirst(prefix.count + 1))
        }
        return nil
    }

    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg == "--help" || arg == "-h" {
            printUsageAndExit()
        } else if let v = popValue("--duration", arg) {
            config.durationSeconds = TimeInterval(v) ?? config.durationSeconds
        } else if let v = popValue("--interval", arg) {
            config.printIntervalSeconds = TimeInterval(v) ?? config.printIntervalSeconds
        } else if let v = popValue("--db-on", arg) {
            config.dbOn = Double(v) ?? config.dbOn
        } else if let v = popValue("--db-off", arg) {
            config.dbOff = Double(v) ?? config.dbOff
        } else if let v = popValue("--min-on", arg) {
            config.minOnSeconds = TimeInterval(v) ?? config.minOnSeconds
        } else if let v = popValue("--min-off", arg) {
            config.minOffSeconds = TimeInterval(v) ?? config.minOffSeconds
        } else if let v = popValue("--stale", arg) {
            config.staleTimeoutSeconds = TimeInterval(v) ?? config.staleTimeoutSeconds
        } else if let v = popValue("--out", arg) {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                config.outputPath = trimmed
            }
        } else if let v = popValue("--device", arg) {
            config.outputDeviceKind = v.lowercased()
        } else if let v = popValue("--exclude", arg) {
            config.excludeBundleIDSubstrings.append(v)
        } else if arg == "--no-default-exclude" {
            config.excludeBundleIDSubstrings.removeAll()
        } else {
            fputs("Unknown argument: \(arg)\n", stderr)
            printUsageAndExit()
        }
        i += 1
    }

    if config.dbOff > config.dbOn {
        // Ensure hysteresis direction makes sense; fall back to defaults.
        config.dbOn = -45
        config.dbOff = -55
    }

    if config.outputDeviceKind != "output" && config.outputDeviceKind != "system" {
        fputs("Invalid --device value: \(config.outputDeviceKind)\n", stderr)
        printUsageAndExit()
    }

    return config
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isValid: Bool { self != .unknown }

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        guard self == .system else { throw ProbeError.coreAudio(-1, "System object required") }
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDefaultOutputDevice() throws -> AudioDeviceID {
        guard self == .system else { throw ProbeError.coreAudio(-1, "System object required") }
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

    func readProcessPID() throws -> pid_t {
        return try read(kAudioProcessPropertyPID, defaultValue: pid_t(0))
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
            throw ProbeError.coreAudio(err, "AudioObjectGetPropertyDataSize failed for selector \(address.mSelector)")
        }

        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, pointer)
        }
        guard err == noErr else {
            throw ProbeError.coreAudio(err, "AudioObjectGetPropertyData failed for selector \(address.mSelector)")
        }

        return value
    }
}

func getProcessObjectList() throws -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    let status1 = AudioObjectGetPropertyDataSize(.system, &address, 0, nil, &dataSize)
    guard status1 == noErr else {
        throw ProbeError.coreAudio(status1, "Failed to get process object list size")
    }
    if dataSize == 0 {
        return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var objects = Array<AudioObjectID>(repeating: .unknown, count: count)
    var dataSizeCopy = dataSize
    let status2 = AudioObjectGetPropertyData(.system, &address, 0, nil, &dataSizeCopy, &objects)
    guard status2 == noErr else {
        throw ProbeError.coreAudio(status2, "Failed to read process object list")
    }

    let finalCount = Int(dataSizeCopy) / MemoryLayout<AudioObjectID>.size
    return Array(objects.prefix(finalCount))
}

func findExcludedProcessObjectIDs(config: Config) throws -> ([AudioObjectID], [String]) {
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

final class SharedState {
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

func fourCC(_ status: OSStatus) -> String {
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

func computeRMS(bufferList: UnsafePointer<AudioBufferList>, asbd: AudioStreamBasicDescription) -> Double? {
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
        // One buffer per channel.
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
        // Interleaved: usually a single buffer.
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

final class OutputSink {
    private var handle: FileHandle?

    func configure(outputPath: String?) throws {
        guard let outputPath else { return }

        let url = URL(fileURLWithPath: outputPath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: outputPath, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func writeLine(_ line: String) {
        guard let handle else {
            print(line)
            return
        }
        if let data = (line + "\n").data(using: .utf8) {
            handle.write(data)
            handle.synchronizeFile()
        }
    }

    deinit {
        try? handle?.close()
    }
}

let outputSink = OutputSink()

func emitJSON(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
       let line = String(data: data, encoding: .utf8) {
        outputSink.writeLine(line)
    } else {
        // Fallback to something parseable.
        outputSink.writeLine("{\"type\":\"error\",\"message\":\"failed to encode json\"}")
    }
}

let config = parseArgs()

if let outputPath = config.outputPath {
    do {
        try outputSink.configure(outputPath: outputPath)
    } catch {
        emitJSON([
            "type": "error",
            "timestamp": Date().timeIntervalSince1970,
            "message": "Failed to open --out path: \(outputPath) (\(error))"
        ])
        exit(1)
    }
}

guard #available(macOS 14.2, *) else {
    emitJSON(["type": "error", "message": ProbeError.unsupportedOS.localizedDescription])
    exit(2)
}

do {
    let (excludedProcessIDs, matchedBundleIDs) = try findExcludedProcessObjectIDs(config: config)

    // Resolve output device UID
    let outputDeviceID: AudioDeviceID
    if config.outputDeviceKind == "system" {
        outputDeviceID = try AudioObjectID.system.readDefaultSystemOutputDevice()
    } else {
        outputDeviceID = try AudioObjectID.system.readDefaultOutputDevice()
    }
    guard outputDeviceID.isValid else { throw ProbeError.missingDefaultOutputDevice }
    let outputUID = try outputDeviceID.readDeviceUID()

    // Build tap
    let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcessIDs)
    tapDescription.uuid = UUID()
    tapDescription.muteBehavior = .unmuted
    tapDescription.isPrivate = true

    var tapID: AudioObjectID = .unknown
    var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
    guard err == noErr else { throw ProbeError.coreAudio(err, "AudioHardwareCreateProcessTap failed (\(fourCC(err)))") }

    // Read tap format
    let tapASBD = try tapID.readAudioTapStreamBasicDescription()

    // Create aggregate device with the tap
    let aggregateUID = UUID().uuidString
    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey: "CloudYield Tap Probe",
        kAudioAggregateDeviceUIDKey: aggregateUID,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        // Start IO when the tap actually receives audio.
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

    var aggregateDeviceID: AudioObjectID = .unknown
    err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
    guard err == noErr else { throw ProbeError.coreAudio(err, "AudioHardwareCreateAggregateDevice failed (\(fourCC(err)))") }

    let state = SharedState()
    let queue = DispatchQueue(label: "CloudYield.ProcessTapProbe", qos: .userInitiated)
    var deviceProcID: AudioDeviceIOProcID?

    let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
        if let rms = computeRMS(bufferList: inInputData, asbd: tapASBD) {
            let db = 20.0 * log10(max(rms, 1e-9))
            state.update(db: db)
        }
    }

    err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
    guard err == noErr else { throw ProbeError.coreAudio(err, "AudioDeviceCreateIOProcIDWithBlock failed (\(fourCC(err)))") }

    err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
    guard err == noErr else { throw ProbeError.coreAudio(err, "AudioDeviceStart failed (\(fourCC(err)))") }

    emitJSON([
        "type": "start",
        "timestamp": Date().timeIntervalSince1970,
        "duration": config.durationSeconds,
        "interval": config.printIntervalSeconds,
        "dbOn": config.dbOn,
        "dbOff": config.dbOff,
        "deviceKind": config.outputDeviceKind,
        "excludedProcessCount": excludedProcessIDs.count,
        "excludedBundleIDs": matchedBundleIDs,
        "tapFormat": [
            "formatID": tapASBD.mFormatID,
            "channels": tapASBD.mChannelsPerFrame,
            "sampleRate": tapASBD.mSampleRate,
            "bitsPerChannel": tapASBD.mBitsPerChannel,
            "bytesPerFrame": tapASBD.mBytesPerFrame,
            "formatFlags": tapASBD.mFormatFlags
        ]
    ])

    // State machine with hysteresis + min durations.
    var audible = false
    var pendingTarget: Bool?
    var pendingSince: Date?

    func stableDuration(for target: Bool) -> TimeInterval {
        target ? config.minOnSeconds : config.minOffSeconds
    }

    func tick() {
        let now = Date()
        var (db, age) = state.snapshot(now: now)
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
        } else {
            if pendingTarget != immediateTarget {
                pendingTarget = immediateTarget
                pendingSince = now
            } else if let since = pendingSince, now.timeIntervalSince(since) >= stableDuration(for: immediateTarget) {
                audible = immediateTarget
                pendingTarget = nil
                pendingSince = nil
                emitJSON([
                    "type": "event",
                    "timestamp": now.timeIntervalSince1970,
                    "db": db.isFinite ? db : NSNull(),
                    "audible": audible
                ])
            }
        }

        emitJSON([
            "type": "status",
            "timestamp": now.timeIntervalSince1970,
            "db": db.isFinite ? db : NSNull(),
            "audible": audible,
            "callbackAge": age
        ])
    }

    let endDate = Date().addingTimeInterval(config.durationSeconds)
    let timer = Timer.scheduledTimer(withTimeInterval: config.printIntervalSeconds, repeats: true) { _ in
        tick()
    }
    RunLoop.current.run(until: endDate)
    timer.invalidate()

    // Cleanup
    _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
    if let deviceProcID {
        _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
    }
    _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
    _ = AudioHardwareDestroyProcessTap(tapID)

    emitJSON([
        "type": "end",
        "timestamp": Date().timeIntervalSince1970
    ])
} catch {
    emitJSON([
        "type": "error",
        "timestamp": Date().timeIntervalSince1970,
        "message": (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    ])
    exit(1)
}
