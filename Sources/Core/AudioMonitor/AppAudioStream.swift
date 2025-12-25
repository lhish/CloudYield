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

    // 节流：限制回调频率
    private var lastCallbackTime: Date = .distantPast
    private let callbackInterval: TimeInterval = 1.0  // 每1秒最多1次回调

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

        // 创建配置 - 只捕获音频，完全禁用视频
        let config = SCStreamConfiguration()

        // 音频配置
        config.capturesAudio = true
        config.sampleRate = 8000   // 8kHz
        config.channelCount = 1    // 单声道
        config.excludesCurrentProcessAudio = true

        // 尝试完全禁用视频
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1000, timescale: 1)  // 每1000秒1帧
        config.queueDepth = 1
        config.showsCursor = false

        // 获取显示器和应用，使用 OBS 的过滤器方式
        // display + includingApplications（而不是 desktopIndependentWindow）
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw NSError(domain: "AppAudioStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "找不到显示器"])
        }

        // 创建过滤器：display + including（OBS 方式）
        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )

        logDebug("创建过滤器: display+including(\(application.applicationName))", module: "AppAudioStream")

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
            sampleHandlerQueue: nil
        )

        // 必须添加视频输出，否则 SCStream 无法启动
        // 但我们配置了最小化的视频参数（1x1像素，每1000秒1帧）来减少资源占用
        try stream?.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: nil
        )

        // 启动捕获（支持取消）
        try await withTaskCancellationHandler {
            try await stream?.startCapture()
        } onCancel: {
            // 如果任务被取消，停止流
            Task {
                try? await self.stream?.stopCapture()
            }
        }

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
        let oldVolume = currentVolume
        currentVolume = dB

        // 智能节流：音量变化大时立即响应，否则限制频率
        let now = Date()
        let volumeChanged = abs(dB - oldVolume) > 5.0  // 音量变化超过5dB
        let shouldCallback = volumeChanged || now.timeIntervalSince(lastCallbackTime) >= callbackInterval

        if shouldCallback {
            lastCallbackTime = now

            // 触发回调
            onVolumeChanged?(dB)

            // 只记录有意义的音量（避免日志过多）
            if dB > -40 {
                logDebug("[\(application.applicationName)] 音量: \(String(format: "%.1f", dB)) dB", module: "AppAudioStream")
            }
        }
    }

    /// 从 CMSampleBuffer 提取音频采样数据
    /// 使用 OBS 的方式：直接访问 CMBlockBuffer，避免 AudioBufferList
    private func extractAudioSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        // 获取格式描述
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        // 获取音频流基本描述
        guard let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        let channelCount = Int(audioDesc.pointee.mChannelsPerFrame)
        guard channelCount > 0 else {
            return nil
        }

        // 获取 CMBlockBuffer（OBS 方式）
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        // 直接获取数据指针
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let bytes = dataPointer else {
            return nil
        }

        // 转换为 Float 指针
        let floatPtr = UnsafeRawPointer(bytes).assumingMemoryBound(to: Float.self)
        let frameCount = totalLength / MemoryLayout<Float>.size

        // 转换为 Swift 数组
        let samples = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))

        // 输出前几个采样值用于调试（仅在首次捕获时）
        if firstCapture && !samples.isEmpty {
            let samplePreview = samples.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            logDebug("[\(application.applicationName)] 首次音频采样: [\(samplePreview)...] (共 \(frameCount) 帧, \(channelCount) 通道)", module: "AppAudioStream")
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
