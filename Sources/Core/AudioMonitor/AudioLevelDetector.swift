//
//  AudioLevelDetector.swift
//  StillMusicWhenBack
//
//  音频级别检测器 - 计算 RMS、Peak 值并智能判断是否有有效声音
//

import Foundation
import AVFoundation
import Accelerate

class AudioLevelDetector {
    // MARK: - Properties

    // 基线噪音级别（dB）
    private var baselineNoiseLevel: Float = -60.0
    private var isLearningBaseline = false
    private var baselineSamples: [Float] = []
    private let baselineDuration: TimeInterval = 10.0 // 学习10秒基线

    // 检测阈值（相对于基线的偏移，单位：dB）
    private let thresholdOffset: Float = 15.0

    // 滑动窗口，用于平滑音量波动
    private var recentLevels: [Float] = []
    private let windowSize = 5

    // 回调
    var onSignificantSoundDetected: ((Bool) -> Void)?

    private var lastSignificantSound: Bool = false

    // MARK: - Public Methods

    /// 开始基线学习
    func startBaselineLearning() {
        logInfo("开始学习环境噪音基线（10秒）...", module: "AudioDetector")
        isLearningBaseline = true
        baselineSamples = []

        // 10秒后结束基线学习
        DispatchQueue.main.asyncAfter(deadline: .now() + baselineDuration) { [weak self] in
            self?.finishBaselineLearning()
        }
    }

    /// 处理音频缓冲区
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        logDebug("开始处理音频缓冲区...", module: "AudioDetector")

        guard let channelData = buffer.floatChannelData else {
            logError("channelData 为 nil!", module: "AudioDetector")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        logDebug("帧长度: \(frameLength), 声道数: \(channelCount)", module: "AudioDetector")

        // 计算 RMS（均方根）
        var rms: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var channelRMS: Float = 0.0

            // 使用 vDSP 加速计算
            vDSP_rmsqv(samples, 1, &channelRMS, vDSP_Length(frameLength))

            rms += channelRMS
        }

        // 取平均
        rms /= Float(channelCount)

        // 转换为 dB
        let dB = amplitudeToDecibels(rms)

        logDebug("RMS: \(String(format: "%.6f", rms)), dB: \(String(format: "%.1f", dB))", module: "AudioDetector")

        // 如果正在学习基线
        if isLearningBaseline {
            logDebug("正在学习基线，样本数: \(baselineSamples.count + 1)", module: "AudioDetector")
            baselineSamples.append(dB)
            return
        }

        // 添加到滑动窗口
        recentLevels.append(dB)
        if recentLevels.count > windowSize {
            recentLevels.removeFirst()
        }

        // 计算平滑后的音量
        let smoothedLevel = recentLevels.reduce(0, +) / Float(recentLevels.count)

        // 判断是否有显著声音
        let threshold = baselineNoiseLevel + thresholdOffset
        let hasSignificantSound = smoothedLevel > threshold

        logDebug("平滑音量: \(String(format: "%.1f", smoothedLevel)) dB, 阈值: \(String(format: "%.1f", threshold)) dB, 有声音: \(hasSignificantSound)", module: "AudioDetector")

        // 只在状态变化时触发回调
        if hasSignificantSound != lastSignificantSound {
            lastSignificantSound = hasSignificantSound

            if hasSignificantSound {
                logInfo("🔊 检测到显著声音: \(String(format: "%.1f", smoothedLevel)) dB (基线: \(String(format: "%.1f", baselineNoiseLevel)) dB)", module: "AudioDetector")
            } else {
                logInfo("🔇 声音消失", module: "AudioDetector")
            }

            logDebug("触发回调，hasSound: \(hasSignificantSound)", module: "AudioDetector")
            onSignificantSoundDetected?(hasSignificantSound)
        }
    }

    // MARK: - Private Methods

    private func finishBaselineLearning() {
        isLearningBaseline = false

        guard !baselineSamples.isEmpty else {
            logWarning("基线学习失败，使用默认值", module: "AudioDetector")
            return
        }

        // 计算基线（取中位数，避免异常值影响）
        let sortedSamples = baselineSamples.sorted()
        let medianIndex = sortedSamples.count / 2
        baselineNoiseLevel = sortedSamples[medianIndex]

        logSuccess("基线学习完成: \(String(format: "%.1f", baselineNoiseLevel)) dB", module: "AudioDetector")
        logInfo("检测阈值: \(String(format: "%.1f", baselineNoiseLevel + thresholdOffset)) dB", module: "AudioDetector")

        baselineSamples = []
    }

    /// 将振幅转换为分贝
    private func amplitudeToDecibels(_ amplitude: Float) -> Float {
        // 避免 log(0)
        let safeAmplitude = max(amplitude, 1e-10)

        // 转换为 dB (参考值: 1.0)
        return 20 * log10(safeAmplitude)
    }
}
