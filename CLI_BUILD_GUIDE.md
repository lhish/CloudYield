# 命令行构建和运行指南

## 🎉 已使用命令行成功构建！

项目已使用 Swift Package Manager 成功构建，无需打开 Xcode！

---

## 📦 构建状态

✅ **Swift Package Manager 配置完成**
✅ **所有源代码文件已编译**
✅ **可执行文件已生成**

构建产物位置：`.build/debug/StillMusicWhenBack` (396 KB)

---

## 🚀 快速开始（3个命令）

### 方法1：直接运行（推荐）

```bash
# 1. 授予必要权限后直接运行
.build/debug/StillMusicWhenBack
```

**注意**：首次运行需要授予系统权限（见下方"权限配置"）

### 方法2：使用 swift run

```bash
# 直接构建并运行
swift run
```

---

## 🔧 完整构建命令

### 构建项目

```bash
# Debug 模式构建（默认）
swift build

# Release 模式构建（优化性能）
swift build -c release

# 查看构建产物
ls -lh .build/debug/StillMusicWhenBack
# 或 Release 版本
ls -lh .build/release/StillMusicWhenBack
```

### 清理构建

```bash
# 清理所有构建产物
swift package clean

# 或使用 rm
rm -rf .build
```

### 更新依赖

```bash
# 如果添加了新的依赖包
swift package update
```

---

## 🔐 权限配置（重要！）

应用首次运行时需要授予以下权限：

### 1. 屏幕录制权限（必需）

**用途**：捕获系统音频

**授予方法**：
```bash
# 1. 打开系统设置
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

# 2. 在弹出的窗口中勾选 "StillMusicWhenBack" 或 "Terminal"（如果从终端运行）

# 3. 重启应用
.build/debug/StillMusicWhenBack
```

### 2. 辅助功能权限（必需）

**用途**：控制网易云音乐

**授予方法**：
```bash
# 1. 打开系统设置
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

# 2. 勾选 "StillMusicWhenBack" 或 "Terminal"

# 3. 重启应用
```

---

## 🧪 测试应用

### 测试步骤

1. **启动网易云音乐并播放歌曲**
   ```bash
   open -a "NeteaseMusic"
   ```

2. **在新终端窗口运行应用**
   ```bash
   .build/debug/StillMusicWhenBack
   ```

3. **播放测试视频（浏览器）**
   - 打开 YouTube 或任何视频网站
   - 播放一个视频
   - 观察：3秒后网易云音乐应该自动暂停

4. **停止视频**
   - 关闭视频或静音
   - 观察：3秒后网易云音乐应该自动恢复播放

5. **查看日志输出**
   - 终端会显示详细的状态转换日志
   - 可以看到音频检测和状态变化

### 示例日志输出

```
[App] 应用启动...
[AudioMonitor] 正在启动音频监控...
[AudioDetector] 开始学习环境噪音基线（10秒）...
[AudioMonitor] ✅ 音频监控已启动
[StateEngine] 启动状态引擎
[StateEngine] 状态变化: 空闲 → 正在监控
[App] 应用启动完成

[AudioDetector] ✅ 基线学习完成: -45.2 dB
[AudioDetector] 检测阈值: -30.2 dB

[AudioDetector] 🔊 检测到显著声音: -25.8 dB (基线: -45.2 dB)
[StateEngine] 检测到声音，开始计时...
[StateEngine] 状态变化: 正在监控 → 检测到声音...
[DelayTimer] 启动计时器，延迟 3.0 秒

[DelayTimer] ⏰ 计时器到期
[StateEngine] ⏰ 检测计时器到期
[StateEngine] 网易云正在播放，准备暂停...
[MusicController] 暂停播放...
[MusicController] ✅ 已暂停
[StateEngine] 状态变化: 检测到声音... → 已暂停音乐

[AudioDetector] 🔇 声音消失
[StateEngine] 其他声音停止，开始恢复计时...
[StateEngine] 状态变化: 已暂停音乐 → 等待恢复...

[DelayTimer] ⏰ 计时器到期
[StateEngine] ⏰ 恢复计时器到期
[StateEngine] 恢复网易云播放...
[MusicController] 恢复播放...
[MusicController] ✅ 已恢复播放
[StateEngine] 状态变化: 等待恢复... → 正在监控
```

---

## 📱 创建独立应用（可选）

### 方法1：使用 Release 构建

```bash
# 构建 Release 版本
swift build -c release

# 复制到 Applications 文件夹
cp .build/release/StillMusicWhenBack ~/Applications/

# 或系统 Applications
sudo cp .build/release/StillMusicWhenBack /Applications/
```

### 方法2：创建 macOS 应用包

```bash
# 生成 Xcode 项目（用于创建 .app bundle）
swift package generate-xcodeproj

# 然后在 Xcode 中构建，会生成 .app 文件
open StillMusicWhenBack.xcodeproj
```

---

## 🔄 配置开机自启动（可选）

### 方法1：使用 launchd

创建启动脚本：

```bash
# 创建 plist 文件
cat > ~/Library/LaunchAgents/com.stillmusic.app.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stillmusic.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/lhy/CLionProjects/still_music_when_back/.build/release/StillMusicWhenBack</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# 加载启动项
launchctl load ~/Library/LaunchAgents/com.stillmusic.app.plist

# 卸载启动项
# launchctl unload ~/Library/LaunchAgents/com.stillmusic.app.plist
```

---

## 🐛 故障排除

### 问题1：权限被拒绝

```bash
# 错误信息
# [AudioMonitor] ❌ 启动失败: Error Domain=...

# 解决方法
# 1. 确保已授予屏幕录制权限
# 2. 重启终端
# 3. 重新运行应用
```

### 问题2：无法控制网易云

```bash
# 确保网易云音乐正在运行
pgrep -fl NeteaseMusic

# 如果没有运行，启动它
open -a "NeteaseMusic"
```

### 问题3：构建失败

```bash
# 清理并重新构建
swift package clean
swift build

# 查看详细错误
swift build -v
```

### 问题4：菜单栏图标不显示

**原因**：命令行应用默认没有 UI
**解决**：使用 Xcode 构建 .app bundle，或者在代码中查看状态变化

---

## 📊 性能监控

### 查看 CPU 和内存使用

```bash
# 运行应用
.build/debug/StillMusicWhenBack &

# 获取进程 PID
PID=$(pgrep -f StillMusicWhenBack)

# 监控资源使用
top -pid $PID

# 或使用 ps
ps -p $PID -o %cpu,%mem,vsz,rss
```

预期：
- **CPU**: < 1% （空闲时）
- **内存**: < 50 MB

---

## 🎯 开发工作流

### 修改代码后重新构建

```bash
# 1. 编辑源文件
vim Sources/Core/StateManager/StateTransitionEngine.swift

# 2. 重新构建
swift build

# 3. 运行测试
.build/debug/StillMusicWhenBack
```

### 使用 watch 模式（自动重新构建）

```bash
# 安装 fswatch（如果没有）
brew install fswatch

# 监控文件变化并自动构建
fswatch -o Sources | while read; do
    echo "检测到文件变化，重新构建..."
    swift build
done
```

---

## 📚 更多命令

### Swift Package Manager 常用命令

```bash
# 查看包信息
swift package describe

# 显示依赖树
swift package show-dependencies

# 解析依赖
swift package resolve

# 初始化新包（如果从头开始）
swift package init --type executable

# 生成 Xcode 项目
swift package generate-xcodeproj

# 运行测试（如果有）
swift test
```

---

## ✅ 总结

您现在已经成功：
- ✅ 使用命令行构建项目
- ✅ 无需打开 Xcode
- ✅ 生成可执行文件
- ✅ 可以直接运行和测试

**下一步**：
1. 运行应用并测试功能
2. 查看日志输出
3. 根据需要调整代码
4. 享受智能音乐体验！

---

*生成时间: 2025-12-25*
*构建工具: Swift Package Manager*
