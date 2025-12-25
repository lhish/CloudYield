import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Accelerate

/// 单个应用的音频流监控
/// 参考 OBS Studio 的 mac-sck-audio-capture.m 实现
class AppAudioStream: NSObject {
    // MARK: - Properties

    let application: SCRunningApplication
    private var stream: SCStream?
    private var currentVolume: Float = 0.0
    private var isCapturing = false
    private var firstCapture = true  // 用于调试输出

    private let audioQueue = DispatchQueue(
        label: "com.stillmusic.appstream.\(UUID().uuidString)",
        qos: .userInteractive
    )

    // 回调
    var onVolumeChanged: ((Float) -> Void)?

    // MARK: - Initialization

    init(application: SCRunningApplication) {
        self.application = application
        super.init()
    }

    // MARK: - Public Methods

    /// 开始捕获音频
    func startCapture() async throws {
        guard !isCapturing else { return }

        logInfo("🎵 开始捕获应用音频: \(application.applicationName)", module: "AppAudioStream")

        // 创建配置
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        // 最小视频配置（ScreenCaptureKit 要求必须配置视频）
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        // 创建应用特定的过滤器
        // 根据 ScreenCaptureKit 文档，音频过滤只能在应用级别工作
        // 我们需要使用 display + excluding 来实现应用级音频捕获
        guard let display = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).displays.first else {
            throw NSError(domain: "AppAudioStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "找不到显示器"])
        }

        // 排除所有应用，只保留我们要监控的这一个应用
        let allApps = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).applications
        let appsToExclude = allApps.filter { $0.bundleIdentifier != application.bundleIdentifier }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: appsToExclude,
            exceptingWindows: []
        )

        logDebug("创建过滤器: desktopIndependentWindow(\(application.applicationName))", module: "AppAudioStream")

        // 创建流
        stream = SCStream(
            filter: filter,
            configuration: config,
            delegate: self
        )

        // 添加音频输出
        try stream?.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: audioQueue
        )

        // 启动捕获
        try await stream?.startCapture()

        isCapturing = true
        logSuccess("✅ 应用音频捕获已启动: \(application.applicationName)", module: "AppAudioStream")
    }

    /// 停止捕获
    func stopCapture() async {
        guard isCapturing else { return }

        logInfo("⏸️ 停止捕获应用音频: \(application.applicationName)", module: "AppAudioStream")

        do {
            try await stream?.stopCapture()
        } catch {
            logError("停止捕获失败: \(error)", module: "AppAudioStream")
        }

        stream = nil
        isCapturing = false
        currentVolume = 0.0
    }

    /// 获取当前音量
    func getCurrentVolume() -> Float {
        return currentVolume
    }

    /// 是否正在捕获
    func getIsCapturing() -> Bool {
        return isCapturing
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let samples = extractAudioSamples(from: sampleBuffer) else {
            return
        }

        // 计算 RMS
        let rms = calculateRMS(samples: samples)
        let dB = amplitudeToDecibels(rms)

        // 更新音量
        currentVolume = dB

        // 触发回调
        onVolumeChanged?(dB)

        // 只记录有意义的音量（避免日志过多）
        if dB > -40 {
            logDebug("[\(application.applicationName)] 音量: \(String(format: "%.1f", dB)) dB", module: "AppAudioStream")
        }
    }

    /// 从 CMSampleBuffer 提取音频采样数据
    /// 参考 OBS 的 screen_stream_audio_update 实现
    private func extractAudioSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        // 首先获取需要的 AudioBufferList 大小
        var bufferListSizeNeeded: Int = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        guard status == noErr || status == kCMSampleBufferError_BufferHasNoSampleSizes else {
            logError("获取 AudioBufferList 大小失败: OSStatus=\(status)", module: "AppAudioStream")
            return nil
        }

        // 分配足够的内存
        let audioBufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { audioBufferListPointer.deallocate() }

        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPointer,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        defer { blockBuffer = nil }

        guard status == noErr else {
            logError("提取音频缓冲区失败: OSStatus=\(status)", module: "AppAudioStream")
            return nil
        }

        // 从 AudioBufferList 中提取 Float 数据
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferListPointer)

        guard let buffer = ablPointer.first,
              let data = buffer.mData else {
            return nil
        }

        let floatPtr = data.assumingMemoryBound(to: Float.self)
        let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size

        // 转换为 Swift 数组
        let samples = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))

        // 输出前几个采样值用于调试（仅在首次捕获时）
        if firstCapture && !samples.isEmpty {
            let samplePreview = samples.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            logDebug("[\(application.applicationName)] 首次音频采样: [\(samplePreview)...] (共 \(frameCount) 帧)", module: "AppAudioStream")
            firstCapture = false
        }

        return samples
    }

    /// 计算 RMS（均方根）
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    /// 将振幅转换为分贝值
    private func amplitudeToDecibels(_ amplitude: Float) -> Float {
        let safeAmplitude = max(amplitude, 1e-10) // 防止 log(0)
        return 20 * log10(safeAmplitude)
    }
}

// MARK: - SCStreamDelegate
extension AppAudioStream: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logError("❌ [\(application.applicationName)] 流停止，错误: \(error)", module: "AppAudioStream")
        isCapturing = false
        currentVolume = 0.0
    }
}

// MARK: - SCStreamOutput
extension AppAudioStream: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        // 只处理音频输出
        guard outputType == .audio else { return }
        processAudioBuffer(sampleBuffer)
    }
}
