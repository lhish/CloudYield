# 🐛 调试指南

## 已添加详细调试日志！

现在运行应用会输出**非常详细**的调试信息，帮助定位问题。

---

## 🚀 快速调试步骤

### 1. 运行应用（保留日志输出）

```bash
# 方法1：从命令行运行（推荐调试）
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack

# 方法2：使用日志流
open StillMusicWhenBack.app
log stream --predicate 'process == "StillMusicWhenBack"' --level debug
```

### 2. 观察日志输出

**预期的完整日志流程：**

```
[App] 应用启动...
[App] ✅ 已有屏幕录制权限（或请求权限）
[App] ✅ 已有辅助功能权限（或请求权限）

[AudioMonitor] 🔧 [DEBUG] 正在启动音频监控...
[AudioMonitor] 🔧 [DEBUG] 检测器已设置: true
[AudioMonitor] 🔧 [DEBUG] 回调已设置: true
[AudioMonitor] 🔧 [DEBUG] 步骤1: 获取可捕获内容...
[AudioMonitor] 🔧 [DEBUG] 找到 1 个显示器
[AudioMonitor] 🔧 [DEBUG] 找到 XX 个窗口
[AudioMonitor] 🔧 [DEBUG] 步骤2: 创建音频配置...
[AudioMonitor] 🔧 [DEBUG] 音频配置: 采样率=48000, 声道=2
[AudioMonitor] 🔧 [DEBUG] 步骤3: 创建内容过滤器...
[AudioMonitor] 🔧 [DEBUG] 使用显示器: <SCDisplay: ...>
[AudioMonitor] 🔧 [DEBUG] 过滤器创建成功
[AudioMonitor] 🔧 [DEBUG] 步骤4: 创建 SCStream...
[AudioMonitor] 🔧 [DEBUG] SCStream 创建成功
[AudioMonitor] 🔧 [DEBUG] 步骤5: 添加音频输出处理...
[AudioMonitor] 🔧 [DEBUG] 音频输出处理已添加
[AudioMonitor] 🔧 [DEBUG] 步骤6: 启动捕获...
[AudioMonitor] ✅ 音频监控已启动成功！
[AudioMonitor] 🔧 [DEBUG] 启动基线学习...

[AudioDetector] 开始学习环境噪音基线（10秒）...

[StateEngine] 启动状态引擎
[StateEngine] 状态变化: 空闲 → 正在监控

[App] ✅ 音频监控已启动
[App] ✅ 状态引擎已启动
[App] 应用启动完成

（等待10秒基线学习...）

[AudioMonitor] 🔧 [DEBUG] 收到音频缓冲区
[AudioDetector] 🔧 [DEBUG] 开始处理音频缓冲区...
[AudioDetector] 🔧 [DEBUG] 帧长度: 4096, 声道数: 2
[AudioDetector] 🔧 [DEBUG] RMS: 0.001234, dB: -48.2
[AudioDetector] 🔧 [DEBUG] 正在学习基线，样本数: 1

（持续接收音频...）

[AudioDetector] ✅ 基线学习完成: -45.2 dB
[AudioDetector] 检测阈值: -30.2 dB

（当有声音时...）

[AudioDetector] 🔧 [DEBUG] 平滑音量: -25.8 dB, 阈值: -30.2 dB, 有声音: true
[AudioDetector] 🔊 检测到显著声音: -25.8 dB (基线: -45.2 dB)
[AudioDetector] 🔧 [DEBUG] 触发回调，hasSound: true
[StateEngine] 🔧 [DEBUG] 收到音频级别变化回调，hasSound: true
[StateEngine] 检测到声音，开始计时...
```

---

## 🔍 问题诊断

### 问题1：没有任何日志输出

**可能原因**：应用没有启动

**解决**：
```bash
# 检查应用是否运行
ps aux | grep StillMusicWhenBack

# 从命令行启动查看错误
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack
```

---

### 问题2：卡在"正在启动音频监控"

**日志显示**：
```
[AudioMonitor] 🔧 [DEBUG] 正在启动音频监控...
（然后没有后续日志）
```

**可能原因**：缺少屏幕录制权限

**解决**：
1. 检查系统设置 → 隐私与安全性 → 屏幕录制
2. 确保勾选了 StillMusicWhenBack
3. 重启应用

---

### 问题3：找到0个显示器

**日志显示**：
```
[AudioMonitor] 🔧 [DEBUG] 找到 0 个显示器
[AudioMonitor] ❌ [DEBUG] 没有找到可用的显示器！
```

**可能原因**：权限问题或系统限制

**解决**：
1. 确认屏幕录制权限
2. 尝试重启Mac
3. 检查是否在远程桌面会话中

---

### 问题4：启动成功但没有收到音频缓冲区

**日志显示**：
```
[AudioMonitor] ✅ 音频监控已启动成功！
[AudioDetector] 开始学习环境噪音基线（10秒）...
（然后再也没有 "收到音频缓冲区" 日志）
```

**可能原因**：
- 音频流没有实际数据
- 系统音频被静音
- 权限问题

**解决**：
```bash
# 1. 播放一些音频（YouTube、音乐等）
open https://www.youtube.com

# 2. 检查系统音量
# 确保不是静音状态

# 3. 查看系统日志
log show --predicate 'subsystem == "com.apple.screencapturekit"' --last 1m
```

---

### 问题5：收到音频但RMS值都是0

**日志显示**：
```
[AudioDetector] 🔧 [DEBUG] RMS: 0.000000, dB: -inf
```

**可能原因**：捕获的是静音音频流

**解决**：
1. 确保有声音在播放
2. 检查音频输出设备是否正确
3. 尝试播放系统声音：
   ```bash
   afplay /System/Library/Sounds/Ping.aiff
   ```

---

### 问题6：检测到声音但网易云没反应

**日志显示**：
```
[AudioDetector] 🔊 检测到显著声音...
[StateEngine] 🔧 [DEBUG] 收到音频级别变化回调，hasSound: true
（但网易云没有暂停）
```

**可能原因**：
- 缺少辅助功能权限
- 网易云没有运行
- AppleScript不工作

**解决**：
```bash
# 1. 检查网易云是否运行
pgrep -fl NeteaseMusic

# 2. 启动网易云
open -a NeteaseMusic

# 3. 检查辅助功能权限
# 系统设置 → 隐私与安全性 → 辅助功能
```

---

## 📋 完整测试清单

### 启动前检查
- [ ] 已授予屏幕录制权限
- [ ] 已授予辅助功能权限
- [ ] 网易云音乐正在运行
- [ ] 网易云正在播放歌曲
- [ ] 系统音量不是静音

### 运行测试
```bash
# 1. 启动应用
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack

# 2. 等待基线学习完成（10秒）
# 应该看到："基线学习完成"

# 3. 播放测试视频
open https://www.youtube.com/watch?v=dQw4w9WgXcQ

# 4. 观察日志
# 预期：检测到声音 → 3秒后暂停网易云

# 5. 停止视频
# 预期：3秒后恢复网易云播放
```

### 日志检查点
1. ✅ "音频监控已启动成功"
2. ✅ "开始学习环境噪音基线"
3. ✅ "收到音频缓冲区"（应该持续出现）
4. ✅ "基线学习完成"
5. ✅ "检测到显著声音"（播放视频时）
6. ✅ "状态变化"日志

---

## 🎯 关键调试日志说明

### 🔧 [DEBUG] 标记
所有带 `🔧 [DEBUG]` 的日志都是调试信息，显示内部运行状态。

### ❌ 错误日志
- 显示详细的错误信息和调用栈
- 帮助定位具体哪一步出错

### ✅ 成功日志
- 表示某个步骤成功完成
- 用于确认流程正常

### 🔊/🔇 音频检测
- 🔊 = 检测到声音
- 🔇 = 声音消失

---

## 💡 高级调试

### 查看系统日志
```bash
# ScreenCaptureKit 日志
log show --predicate 'subsystem == "com.apple.screencapturekit"' --last 5m

# 应用日志
log show --predicate 'process == "StillMusicWhenBack"' --last 5m --style compact
```

### 监控音频设备
```bash
# 查看音频设备列表
system_profiler SPAudioDataType

# 检查音频输出
afplay /System/Library/Sounds/Ping.aiff
```

### 测试 AppleScript
```bash
# 测试网易云控制
osascript -e 'tell application "System Events" to tell process "NeteaseMusic" to get name of menu items of menu "控制" of menu bar item "控制" of menu bar 1'
```

---

## 📊 日志输出到文件

如果日志太多，可以保存到文件：

```bash
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack 2>&1 | tee debug.log
```

然后可以搜索特定关键词：
```bash
grep "ERROR\|❌" debug.log
grep "✅" debug.log
grep "DEBUG" debug.log
```

---

## 🆘 仍然无法解决？

请提供以下信息：

1. **完整的日志输出**（前100行）
2. **卡在哪一步**（最后一条日志是什么）
3. **错误信息**（所有❌标记的日志）
4. **系统信息**：
   ```bash
   sw_vers
   system_profiler SPDisplaysDataType | grep Resolution
   ```

---

*更新时间: 2025-12-25*
*版本: 1.3.0 - 调试版本*
