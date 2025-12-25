# 快速开始指南

## 📦 当前项目状态

✅ **已完成**：
- Git 仓库已初始化
- 所有核心源代码文件已创建并提交
- 项目文档已完成

⏳ **下一步**：
- 在 Xcode 中创建项目
- 添加源代码文件到 Xcode
- 构建和测试

---

## 🚀 5 分钟快速开始

### 步骤 1：创建 Xcode 项目（2分钟）

1. 打开 **Xcode**
2. 选择 **File → New → Project**
3. 选择 **macOS → App**，点击 **Next**
4. 配置项目：
   - Product Name: `StillMusicWhenBack`
   - Organization Identifier: `com.yourdomain`（替换为您的）
   - Interface: **SwiftUI**
   - Language: **Swift**
   - 取消勾选 Use Core Data 和 Include Tests
5. 保存到此目录：`/Users/lhy/CLionProjects/still_music_when_back/`
6. **不要勾选** Create Git repository（我们已经创建了）

### 步骤 2：配置项目设置（2分钟）

#### 2.1 设置最低系统版本
- 选择项目 → TARGET → General
- Minimum Deployments: **macOS 13.0**

#### 2.2 配置权限
1. 找到 `Info.plist`（或 Info 标签页）
2. 右键 → Open As → Source Code
3. 在 `<dict>` 内添加以下内容：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要访问音频以监控系统声音</string>
<key>NSAppleEventsUsageDescription</key>
<string>需要控制网易云音乐的播放状态</string>
<key>LSUIElement</key>
<true/>
<key>NSSupportsAutomaticTermination</key>
<false/>
<key>NSSupportsSuddenTermination</key>
<false/>
```

#### 2.3 添加 Capabilities
- 选择 Signing & Capabilities 标签页
- 点击 + Capability
- 如果有 App Sandbox，勾选：
  - Audio Input
  - Apple Events
  - Outgoing Connections (Client)

### 步骤 3：添加源代码文件（1分钟）

1. **删除默认文件**：
   - 在 Xcode 项目导航器中删除 `ContentView.swift`

2. **创建目录结构**：
   在 Xcode 中右键点击 `StillMusicWhenBack` 文件夹 → New Group，创建：
   ```
   - App
   - Core
     - AudioMonitor
     - MusicController
     - StateManager
     - Timer
   - UI
     - MenuBar
   - Utilities
   ```

3. **拖拽源文件**：
   从 Finder 打开 `/Users/lhy/CLionProjects/still_music_when_back/SourceFiles/`
   将对应文件拖入 Xcode 的对应目录：

   ```
   SourceFiles/App/StillMusicWhenBackApp.swift
     → 拖入 Xcode 的 App/ 目录

   SourceFiles/Core/AudioMonitor/*.swift
     → 拖入 Xcode 的 Core/AudioMonitor/ 目录

   SourceFiles/Core/MusicController/*.swift
     → 拖入 Xcode 的 Core/MusicController/ 目录

   ... 以此类推
   ```

   **注意**：拖拽时勾选 "Copy items if needed"

### 步骤 4：构建和运行

1. 选择目标：**My Mac**
2. 点击 **Run** 按钮（⌘+R）
3. 首次运行会提示授予权限：
   - 点击 **打开系统设置**
   - 授予 **屏幕录制** 和 **辅助功能** 权限
   - 重启应用

---

## 📝 完整详细教程

如果需要更详细的说明，请参考 [SETUP_GUIDE.md](SETUP_GUIDE.md)

---

## ✅ 验证安装

### 1. 检查菜单栏图标
- 运行后应该在菜单栏看到 ✅ 图标
- 点击图标应该看到弹出菜单

### 2. 测试功能
1. 打开网易云音乐并播放歌曲
2. 在浏览器播放一个视频（声音持续 >3 秒）
3. 观察：
   - 菜单栏图标变为 🔊（检测到声音）
   - 3 秒后变为 ⏸（已暂停）
   - 网易云音乐应该已暂停
4. 关闭视频声音
5. 观察：
   - 菜单栏图标变为 ⏳（等待恢复）
   - 3 秒后变回 ✅（正在监控）
   - 网易云音乐应该已恢复播放

### 3. 查看日志
- 在 Xcode 控制台查看详细日志输出
- 可以看到状态转换和音频检测信息

---

## 🐛 常见问题

### 问题 1：编译错误 "Cannot find type 'ScreenCaptureKit'"
**原因**：系统版本 < macOS 13.0 或 Xcode 版本过旧
**解决**：
- 确保 macOS ≥ 13.0
- 确保 Xcode ≥ 15.0
- 检查项目 Minimum Deployments 设置

### 问题 2：无法捕获系统音频
**原因**：未授予屏幕录制权限
**解决**：
1. 系统设置 → 隐私与安全性 → 屏幕录制
2. 勾选 StillMusicWhenBack
3. 重启应用

### 问题 3：无法控制网易云
**原因**：未授予辅助功能权限
**解决**：
1. 系统设置 → 隐私与安全性 → 辅助功能
2. 勾选 StillMusicWhenBack
3. 确保网易云音乐正在运行

---

## 🎉 完成！

现在您已经成功设置并运行了 StillMusicWhenBack！

**下一步建议**：
- ✅ 测试各种场景（浏览器视频、游戏、通话等）
- ✅ 配置开机自启动
- ✅ 根据需要调整代码

**享受智能音乐体验！🎵**

---

## 📚 更多资源

- [详细设置指南](SETUP_GUIDE.md)
- [完整 README](README.md)
- [实现方案文档](../.claude/plans/foamy-waddling-nova.md)

## 🤝 反馈和改进

如果遇到任何问题或有改进建议，请随时提出！
