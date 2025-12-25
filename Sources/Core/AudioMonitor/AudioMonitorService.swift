//
//  AudioMonitorService.swift
//  StillMusicWhenBack
//
//  音频监控服务 - 使用 ScreenCaptureKit 捕获系统音频
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

class AudioMonitorService: NSObject {
    // MARK: - Properties

    private var stream: SCStream?
    private var audioLevelDetector: AudioLevelDetector?
    private let audioQueue = DispatchQueue(label: "com.stillmusic.audio.processing", qos: .userInteractive)

    // 回调：当检测到音频级别变化时
    var onAudioLevelChanged: ((Bool) -> Void)?

    private var isMonitoring = false

    // MARK: - Initialization

    override init() {
        super.init()
        audioLevelDetector = AudioLevelDetector()

        // 设置检测器回调
        audioLevelDetector?.onSignificantSoundDetected = { [weak self] hasSound in
            DispatchQueue.main.async {
                self?.onAudioLevelChanged?(hasSound)
            }
        }
    }

    // MARK: - Public Methods

    /// 开始监控系统音频
    func startMonitoring() async throws {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "AudioMonitor")
            return
        }

        logDebug("正在启动音频监控...", module: "AudioMonitor")
        logDebug("检测器已设置: \(audioLevelDetector != nil)", module: "AudioMonitor")
        logDebug("回调已设置: \(onAudioLevelChanged != nil)", module: "AudioMonitor")

        do {
            // 1. 获取可捕获的内容
            logDebug("步骤1: 获取可捕获内容...", module: "AudioMonitor")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            logDebug("找到 \(content.displays.count) 个显示器", module: "AudioMonitor")
            logDebug("找到 \(content.windows.count) 个窗口", module: "AudioMonitor")

            // 2. 创建配置
            logDebug("步骤2: 创建音频配置...", module: "AudioMonitor")
            let config = SCStreamConfiguration()

            // 音频捕获配置
            config.capturesAudio = true
            config.sampleRate = 48000 // 48kHz 采样率
            config.channelCount = 2   // 立体声
            config.excludesCurrentProcessAudio = false // 不排除本应用的音频,捕获所有系统音频

            // ScreenCaptureKit要求：即使只捕获音频，也必须设置视频参数并启用视频捕获
            // 我们设置最小的视频配置以减少性能开销
            config.width = 2  // 最小宽度(必须>=1)
            config.height = 2 // 最小高度(必须>=1)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS 最低帧率
            config.pixelFormat = kCVPixelFormatType_32BGRA // 设置像素格式
            config.showsCursor = false // 不显示光标
            config.scalesToFit = false // 不缩放

            logDebug("音频配置: 采样率=\(config.sampleRate), 声道=\(config.channelCount)", module: "AudioMonitor")
            logDebug("视频配置(仅用于启用Stream): \(config.width)x\(config.height) @ 1fps", module: "AudioMonitor")

            // 3. 创建内容过滤器（捕获所有音频）
            logDebug("步骤3: 创建内容过滤器...", module: "AudioMonitor")
            guard let display = content.displays.first else {
                logError("没有找到可用的显示器！", module: "AudioMonitor")
                throw NSError(domain: "AudioMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有找到可用的显示器"])
            }
            logDebug("使用显示器: \(display)", module: "AudioMonitor")

            let filter = SCContentFilter(display: display, excludingWindows: [])
            logDebug("过滤器创建成功", module: "AudioMonitor")

            // 4. 创建流
            logDebug("步骤4: 创建 SCStream...", module: "AudioMonitor")
            stream = SCStream(
                filter: filter,
                configuration: config,
                delegate: self
            )
            logDebug("SCStream 创建成功", module: "AudioMonitor")

            // 5. 添加音频输出处理
            logDebug("步骤5: 添加音频输出处理...", module: "AudioMonitor")
            try stream?.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: audioQueue
            )
            logDebug("音频输出处理已添加", module: "AudioMonitor")

            // 6. 启动捕获
            logDebug("步骤6: 启动捕获...", module: "AudioMonitor")
            try await stream?.startCapture()

            isMonitoring = true
            logSuccess("音频监控已启动成功！", module: "AudioMonitor")

            // 启动基线学习
            logDebug("启动基线学习...", module: "AudioMonitor")
            audioLevelDetector?.startBaselineLearning()

        } catch {
            logError("启动失败: \(error)", module: "AudioMonitor")
            logError("错误详情: \(error.localizedDescription)", module: "AudioMonitor")
            throw error
        }
    }

    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止音频监控...", module: "AudioMonitor")

        Task {
            do {
                try await stream?.stopCapture()
                stream = nil
                isMonitoring = false
                logSuccess("音频监控已停止", module: "AudioMonitor")
            } catch {
                logError("停止失败: \(error)", module: "AudioMonitor")
            }
        }
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 提取音频数据
        guard let audioBufferList = getAudioBufferList(from: sampleBuffer) else {
            return
        }

        // 传递给检测器处理
        audioLevelDetector?.processAudioBuffer(audioBufferList)
    }

    private func getAudioBufferList(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        guard let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let format = AVAudioFormat(streamDescription: audioStreamBasicDescription)
        guard let format = format else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // 从 CMSampleBuffer 复制数据到 AVAudioPCMBuffer
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        // 复制数据到PCM buffer
        if let channelData = buffer.floatChannelData {
            // 获取AudioBufferList指针
            let ablPointer = UnsafeMutableAudioBufferListPointer(&audioBufferList)

            for channel in 0..<min(Int(buffer.format.channelCount), Int(ablPointer.count)) {
                guard let sourceData = ablPointer[channel].mData else { continue }

                let source = sourceData.assumingMemoryBound(to: Float.self)
                let destination = channelData[channel]
                let framesToCopy = min(Int(buffer.frameLength), Int(ablPointer[channel].mDataByteSize) / MemoryLayout<Float>.size)

                destination.update(from: source, count: framesToCopy)
            }
        }

        return buffer
    }
}

// MARK: - SCStreamDelegate
extension AudioMonitorService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logError("流停止，错误: \(error)", module: "AudioMonitor")
        isMonitoring = false
    }
}

// MARK: - SCStreamOutput
extension AudioMonitorService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        // 只处理音频输出
        guard outputType == .audio else {
            logDebug("收到非音频输出，类型: \(outputType)", module: "AudioMonitor")
            return
        }

        logDebug("收到音频缓冲区", module: "AudioMonitor")

        // 处理音频缓冲区
        processAudioBuffer(sampleBuffer)
    }
}
