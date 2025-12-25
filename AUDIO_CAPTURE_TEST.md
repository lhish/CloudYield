# 音频捕获功能测试说明

## 当前状态

✅ **已完成:**
- 应用成功启动
- 音频监控服务正常运行
- 正在接收音频缓冲区(960帧/次, 2声道, 48kHz采样率)

⚠️ **待测试:**
- RMS值当前全是0
- 需要播放实际音频验证捕获功能

## 测试步骤

### 1. 播放测试音频

选择以下任一方式播放音频:

**方式A: 使用Safari播放YouTube**
```bash
open -a Safari "https://www.youtube.com/watch?v=dQw4w9WgxcQ"
```

**方式B: 使用系统音乐播放器**
```bash
open -a Music
# 然后播放任意歌曲
```

**方式C: 播放系统音效**
```bash
afplay /System/Library/Sounds/Ping.aiff
```

### 2. 查看日志

```bash
# 实时查看日志
tail -f ~/Library/Logs/StillMusicWhenBack/app.log | grep "RMS"

# 或者查看最近50条RMS日志
tail -200 ~/Library/Logs/StillMusicWhenBack/app.log | grep "RMS" | tail -50
```

### 3. 预期结果

**成功捕获的标志:**
- RMS值 > 0.0
- dB值 > -200.0 (比如 -40.0, -30.0 等)
- 日志显示: `有声音: true`

**示例成功日志:**
```
[2025-12-25 17:40:00.123] 🔧 DEBUG [AudioDetector] RMS: 0.023456, dB: -32.6
[2025-12-25 17:40:00.123] 🔧 DEBUG [AudioDetector] 平滑音量: -32.6 dB, 阈值: -45.0 dB, 有声音: true
```

**失败标志(当前状态):**
```
[2025-12-25 17:39:55.138] 🔧 DEBUG [AudioDetector] RMS: 0.000000, dB: -200.0
[2025-12-25 17:39:55.139] 🔧 DEBUG [AudioDetector] 正在学习基线，样本数: 250
```

## 可能的问题和解决方案

### 问题1: RMS值始终为0

**可能原因:**
1. ScreenCaptureKit捕获的是"屏幕共享时的音频",而不是系统音频输出
2. macOS将音频路由到了不同的设备
3. 音频会话配置问题

**解决方案:**
需要修改捕获策略,可能需要:
- 使用AudioHijack类似的技术
- 使用Core Audio + TAP设备
- 或者改为监控特定应用(网易云音乐)的窗口音频

### 问题2: ScreenCaptureKit的限制

ScreenCaptureKit主要设计用于屏幕录制,其音频捕获功能可能有以下限制:
- 只捕获"正在共享"的窗口的音频
- 无法捕获整个系统的音频输出

**可选方案:**
1. 切换到BlackHole虚拟音频设备
2. 使用Core Audio的AUGraph
3. 直接监控网易云音乐进程的音频输出

## 下一步行动

1. **先测试**: 播放音频,看RMS值是否有变化
2. **如果RMS仍为0**: 说明ScreenCaptureKit无法捕获系统音频
3. **需要重新设计**: 采用其他音频捕获方案

---

**更新时间**: 2025-12-25 17:40
**状态**: 等待用户播放音频进行测试
