# StillMusicWhenBack

一个智能的 macOS 应用，可以在检测到其他声音时自动暂停网易云音乐，并在声音停止后自动恢复播放。

## ✨ 功能特性

- 🎵 **智能音频检测** - 实时监控系统音频输出，智能识别有效声音
- ⏸️ **自动暂停/恢复** - 检测到其他声音持续 3 秒后自动暂停网易云音乐
- 🔄 **自动恢复播放** - 其他声音停止 3 秒后自动恢复播放
- 🚀 **开机自启动** - 支持开机自动启动，后台常驻
- 📊 **菜单栏集成** - 简洁的菜单栏界面，实时显示状态
- 🔒 **隐私保护** - 所有音频处理都在本地完成，不上传任何数据

## 📋 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15.0 或更高版本（用于构建）
- 网易云音乐 macOS 版

## 🛠️ 构建和安装

### 1. 克隆项目

```bash
cd /Users/lhy/CLionProjects/still_music_when_back
```

### 2. 创建 Xcode 项目

请按照 [SETUP_GUIDE.md](SETUP_GUIDE.md) 中的详细步骤创建 Xcode 项目。

### 3. 添加源代码文件

将 `SourceFiles/` 目录中的所有文件添加到 Xcode 项目的对应位置：

```
SourceFiles/
├── App/
│   └── StillMusicWhenBackApp.swift          → 拖入 Xcode 项目的 StillMusicWhenBack/ 目录
├── Core/
│   ├── AudioMonitor/
│   │   ├── AudioMonitorService.swift
│   │   └── AudioLevelDetector.swift
│   ├── MusicController/
│   │   └── NeteaseMusicController.swift
│   ├── StateManager/
│   │   ├── MonitorState.swift
│   │   └── StateTransitionEngine.swift
│   └── Timer/
│       └── DelayTimer.swift
├── UI/
│   └── MenuBar/
│       └── MenuBarController.swift
└── Utilities/
    ├── PermissionManager.swift
    └── LaunchAtLoginManager.swift
```

### 4. 配置权限

在 Xcode 中配置 `Info.plist`（详见 SETUP_GUIDE.md）。

### 5. 构建和运行

1. 在 Xcode 中选择目标为 **My Mac**
2. 点击 **Run** 按钮（⌘+R）
3. 首次运行时授予必要的系统权限

## 🔐 所需权限

应用需要以下系统权限才能正常工作：

### 1. 屏幕录制权限（Screen Recording）

**用途**：监控系统音频输出

**授予方法**：
1. 打开 **系统设置** → **隐私与安全性** → **屏幕录制**
2. 勾选 **StillMusicWhenBack**
3. 重启应用

### 2. 辅助功能权限（Accessibility）

**用途**：控制网易云音乐的播放/暂停

**授予方法**：
1. 打开 **系统设置** → **隐私与安全性** → **辅助功能**
2. 勾选 **StillMusicWhenBack**

## 🎯 使用方法

1. **启动应用**
   - 首次启动时会显示权限请求提示
   - 授予必要权限后应用会在菜单栏显示图标

2. **状态指示**
   - ✅ 正在监控中（绿色勾）
   - 🔊 检测到声音（喇叭）
   - ⏸ 已暂停音乐（暂停符号）
   - ⏳ 等待恢复（沙漏）
   - ⏹ 监控已暂停（停止符号）

3. **控制选项**
   - 点击菜单栏图标查看当前状态
   - 选择 **暂停监控** 临时停止监控
   - 选择 **继续监控** 恢复监控
   - 选择 **退出** 关闭应用

4. **工作流程**
   - 播放网易云音乐
   - 当其他应用（如浏览器视频、游戏等）发出声音时
   - 应用检测到声音持续 3 秒后自动暂停网易云
   - 其他声音停止 3 秒后自动恢复网易云播放

## 🏗️ 架构设计

### 核心模块

1. **AudioMonitorService** - 音频监控服务
   - 使用 ScreenCaptureKit 捕获系统音频
   - 实时分析音频数据

2. **AudioLevelDetector** - 音量检测器
   - 计算 RMS 和 Peak 值
   - 智能阈值算法（基于环境噪音基线）

3. **NeteaseMusicController** - 网易云控制器
   - 通过 AppleScript 控制播放状态
   - 备用方案：键盘快捷键模拟

4. **StateTransitionEngine** - 状态机引擎
   - 协调音频检测和音乐控制
   - 管理延迟计时器

5. **DelayTimer** - 延迟计时器
   - 精确的 3 秒延迟计时
   - 支持取消和重置

6. **MenuBarController** - 菜单栏控制器
   - 显示状态图标
   - 用户交互界面

### 状态转换流程

```
idle → monitoring → detectingOtherSound (3秒计时)
  → musicPaused → waitingResume (3秒计时) → monitoring
```

## 🐛 故障排除

### 问题：无法检测到系统音频

**解决方法**：
1. 确保已授予 **屏幕录制** 权限
2. 在系统设置中勾选 StillMusicWhenBack
3. 重启应用

### 问题：无法控制网易云音乐

**解决方法**：
1. 确保网易云音乐正在运行
2. 授予 **辅助功能** 权限
3. 尝试手动点击网易云的播放/暂停按钮测试

### 问题：误判或延迟

**解决方法**：
1. 应用启动时会学习 10 秒环境噪音基线
2. 确保启动时环境相对安静
3. 如果环境噪音较大，可能需要调整阈值（未来版本将支持）

## 📝 开发日志

- **v1.0.0** (2025-12-25)
  - ✅ 初始版本
  - ✅ 基础音频监控功能
  - ✅ 网易云音乐控制
  - ✅ 状态机实现
  - ✅ 菜单栏界面
  - ✅ 开机自启动支持

## 🔮 未来计划

- [ ] 支持更多音乐应用（Spotify、Apple Music、QQ音乐等）
- [ ] 可配置的延迟时间
- [ ] 可调整的检测灵敏度
- [ ] 应用黑白名单（只监控特定应用的声音）
- [ ] 统计功能（暂停/恢复次数）
- [ ] 偏好设置窗口

## 📄 许可证

MIT License

## 👨‍💻 作者

YourName

## 🙏 致谢

- 使用了 Apple 的 ScreenCaptureKit 框架
- 灵感来源于对更好音乐体验的追求

---

**享受无打扰的音乐时光！🎵**
