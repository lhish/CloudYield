//
//  CoreAudioCaptureService.swift
//  StillMusicWhenBack
//
//  使用 Core Audio 捕获系统音频输出
//  不依赖 ScreenCaptureKit，可以捕获所有音频设备的输出
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

class CoreAudioCaptureService: NSObject {
    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var audioLevelDetector: AudioLevelDetector?
    private var isMonitoring = false

    // 回调：当检测到音频级别变化时
    var onAudioLevelChanged: ((Bool) -> Void)?

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
    func startMonitoring() throws {
        guard !isMonitoring else {
            logInfo("已经在监控中", module: "CoreAudio")
            return
        }

        logDebug("正在启动 Core Audio 监控...", module: "CoreAudio")

        // 创建 AVAudioEngine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw NSError(domain: "CoreAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建 AVAudioEngine"])
        }

        // 获取输入节点 (系统音频输出会路由到这里)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        logDebug("输入格式: 采样率=\(inputFormat.sampleRate), 声道=\(inputFormat.channelCount)", module: "CoreAudio")

        // 安装 Tap 来捕获音频
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer)
        }

        // 准备并启动引擎
        engine.prepare()
        try engine.start()

        isMonitoring = true
        logSuccess("Core Audio 监控已启动成功！", module: "CoreAudio")

        // 启动基线学习
        audioLevelDetector?.startBaselineLearning()
    }

    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }

        logInfo("停止 Core Audio 监控...", module: "CoreAudio")

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isMonitoring = false

        logSuccess("Core Audio 监控已停止", module: "CoreAudio")
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioLevelDetector?.processAudioBuffer(buffer)
    }
}
