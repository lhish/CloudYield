# CloudYield v1.3.0 - 音量淡入淡出功能实现计划

## 用户需求
在暂停/恢复网易云音乐时增加音量淡入淡出效果，作为新版本（1.3.0）发布到 Homebrew。

## 技术方案

### 核心技术
基于 FineTune 开源项目的实现，使用 CoreAudio Process Tap 来拦截和修改网易云音乐的音频流。

### 关键技术要点
1. **创建针对网易云音乐的 Process Tap**
   - 使用 `CATapDescription(stereoMixdownOfProcesses: [neteaseObjectID])`
   - 设置 `muteBehavior = .mutedWhenTapped` 让原始音频静音
   - 所有音频通过 Tap 输出，完全控制音量

2. **音量调整算法**
   - 使用指数平滑：`currentVol += (targetVol - currentVol) * rampCoefficient`
   - 淡出时长：0.5秒（从 1.0 降到 0.0）
   - 淡入时长：0.5秒（从 0.0 升到 1.0）

3. **实时音频处理**
   - 在 AudioDeviceIOBlock 回调中修改音频数据
   - 遵守实时安全约束：无内存分配、无锁、只用原子操作

## 实现步骤

### 1. 创建 NeteaseMusicVolumeController 类
**文件路径**: `Sources/Core/MusicController/NeteaseMusicVolumeController.swift`

**职责**:
- 管理网易云音乐的 Process Tap
- 控制音量淡入淡出
- 处理 Tap 的生命周期

**核心方法**:
- `start()`: 创建并启动 Process Tap
- `stop()`: 停止并销毁 Process Tap
- `fadeOut(duration: TimeInterval, completion: @escaping () -> Void)`: 淡出音量
- `fadeIn(duration: TimeInterval)`: 淡入音量
- `processAudio(_ input: UnsafePointer<AudioBufferList>, to output: UnsafeMutablePointer<AudioBufferList>)`: 音频处理回调

**状态管理**:
- `targetVolume`: 目标音量（0.0-1.0）
- `currentVolume`: 当前音量（平滑过渡）
- `rampCoefficient`: 平滑系数（基于采样率计算）

### 2. 修改 NeteaseMusicController
**文件路径**: `Sources/Core/MusicController/NeteaseMusicController.swift`

**修改内容**:
- 添加 `volumeController` 属性
- 修改 `pause()` 方法：先淡出音量，再暂停播放
- 修改 `play()` 方法：先恢复播放，再淡入音量

**伪代码**:
```swift
func pause() -> Bool {
    guard isRunning() else { return false }

    // 淡出音量（0.5秒）
    volumeController.fadeOut(duration: 0.5) { [weak self] in
        // 淡出完成后暂停播放
        self?.pausePlayback()
    }

    return true
}

func play() -> Bool {
    guard isRunning() else { return false }

    // 先恢复播放
    guard playPlayback() else { return false }

    // 然后淡入音量（0.5秒）
    volumeController.fadeIn(duration: 0.5)

    return true
}
```

### 3. 集成到应用生命周期
**文件路径**: `Sources/App/CloudYieldApp.swift`

**修改内容**:
- 在应用启动时初始化 VolumeController
- 在应用退出时清理资源

### 4. 处理边界情况
- 网易云音乐未运行时的处理
- Process Tap 创建失败的降级方案（回退到无淡入淡出）
- 用户手动操作时的中断处理
- 设备切换时的重启逻辑

## 技术挑战与风险

### 挑战1: 获取网易云音乐的 AudioObjectID
**问题**: 需要从系统的进程列表中找到网易云音乐的 AudioObjectID

**解决方案**:
- 使用 `kAudioHardwarePropertyProcessObjectList` 获取所有音频进程
- 通过 Bundle ID 匹配找到网易云音乐
- 参考 ProcessTapMonitor 中的 `findExcludedProcessObjectIDs()` 方法

### 挑战2: Process Tap 的生命周期管理
**问题**: 何时创建/销毁 Process Tap？

**解决方案**:
- 在网易云音乐启动时创建 Tap
- 在网易云音乐退出时销毁 Tap
- 监听进程列表变化，自动重启 Tap

### 挑战3: 实时音频处理的性能
**问题**: 音频处理必须在实时线程中完成，不能有延迟

**解决方案**:
- 使用原子操作读取音量值
- 避免任何内存分配和锁
- 使用简单的数学运算

### 挑战4: 与现有功能的兼容性
**问题**: 不能影响现有的自动暂停/恢复功能

**解决方案**:
- VolumeController 独立运行，不干扰状态管理
- 只在暂停/恢复时调用淡入淡出
- 保持现有的 AppleScript 控制逻辑

## 降级方案

如果 Process Tap 创建失败或遇到技术障碍：
1. **方案A**: 记录错误，回退到无淡入淡出的直接暂停/恢复
2. **方案B**: 使用延迟暂停/恢复模拟淡入淡出效果（不是真正的音量控制）

## 测试计划

### 功能测试
1. 播放网易云音乐，触发其他应用音频，验证淡出效果
2. 停止其他应用音频，验证淡入效果
3. 快速切换多次，验证稳定性

### 边界测试
1. 网易云音乐未运行时的行为
2. 淡入淡出过程中手动暂停/恢复
3. 设备切换时的处理

### 性能测试
1. CPU 使用率（应该很低）
2. 音频延迟（应该无感知）

## 版本发布

### 版本号更新
- 从 1.2.0 升级到 1.3.0（新功能）

### 需要更新的文件
1. `Package.swift` - 版本号
2. `Sources/Resources/Info.plist` - CFBundleShortVersionString
3. `create_app.sh` - VERSION 变量
4. `README.md` - 功能说明和版本号

### 发布流程
1. 提交代码到 Git
2. 创建 GitHub Release（v1.3.0）
3. 上传 .app 文件
4. 更新 Homebrew tap 仓库的 Cask 文件

## 预估工作量

- 实现 NeteaseMusicVolumeController: ~200行代码
- 修改 NeteaseMusicController: ~50行代码
- 集成和测试: ~50行代码
- 总计: ~300行代码

## 参考资料

- FineTune 开源项目: https://github.com/ronitsingh10/FineTune
- CoreAudio Process Tap 文档
- AudioDeviceIOBlock 文档
