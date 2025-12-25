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
            print("[AudioMonitor] 已经在监控中")
            return
        }

        print("[AudioMonitor] 正在启动音频监控...")

        do {
            // 1. 获取可捕获的内容
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            // 2. 创建配置
            let config = SCStreamConfiguration()

            // 只捕获音频，不捕获视频
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true // 排除本应用的音频

            // 音频配置
            config.sampleRate = 48000 // 48kHz 采样率
            config.channelCount = 2   // 立体声

            // 3. 创建内容过滤器（捕获所有音频）
            // 使用 display 来捕获所有系统音频
            guard let display = content.displays.first else {
                throw NSError(domain: "AudioMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有找到可用的显示器"])
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            // 4. 创建流
            stream = SCStream(
                filter: filter,
                configuration: config,
                delegate: self
            )

            // 5. 添加音频输出处理
            try stream?.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: audioQueue
            )

            // 6. 启动捕获
            try await stream?.startCapture()

            isMonitoring = true
            print("[AudioMonitor] ✅ 音频监控已启动")

            // 启动基线学习
            audioLevelDetector?.startBaselineLearning()

        } catch {
            print("[AudioMonitor] ❌ 启动失败: \(error)")
            throw error
        }
    }

    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }

        print("[AudioMonitor] 停止音频监控...")

        Task {
            do {
                try await stream?.stopCapture()
                stream = nil
                isMonitoring = false
                print("[AudioMonitor] ✅ 音频监控已停止")
            } catch {
                print("[AudioMonitor] ❌ 停止失败: \(error)")
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

        // 复制数据
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                if let sourceData = audioBufferList.mBuffers.mData {
                    let source = sourceData.assumingMemoryBound(to: Float.self)
                    let destination = channelData[channel]
                    destination.update(from: source, count: Int(buffer.frameLength))
                }
            }
        }

        return buffer
    }
}

// MARK: - SCStreamDelegate
extension AudioMonitorService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[AudioMonitor] ❌ 流停止，错误: \(error)")
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
        guard outputType == .audio else { return }

        // 处理音频缓冲区
        processAudioBuffer(sampleBuffer)
    }
}
