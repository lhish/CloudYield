# CloudYield

🎵 让网易云音乐更智能 - 当其他应用播放音频时自动暂停网易云，停止后自动恢复。

## 功能特性

- 🔊 检测到其他应用播放音频时**自动暂停**网易云音乐
- ▶️ 其他应用停止播放后**自动恢复**网易云音乐
- ⚡ 响应速度 **0.1 秒**，几乎无感知
- 🖥️ 菜单栏应用，后台静默运行
- 🚀 支持开机自启

## 使用场景

- 看 B 站视频时自动暂停音乐，关闭视频后自动恢复
- 开会时打开腾讯会议/Zoom 自动暂停音乐
- 玩游戏时自动暂停背景音乐
- 任何需要临时暂停音乐的场景

## 安装

### 依赖

首先安装 `media-control`（用于监控系统 Now Playing 状态）：

```bash
brew install ungive/media-control/media-control
```

### 下载

从 [Releases](https://github.com/lhish/CloudYield/releases) 下载最新版本的 `.app` 文件。

### 从源码构建

```bash
git clone https://github.com/lhish/CloudYield.git
cd CloudYield
swift build -c release
./create_app.sh  # 创建 .app 应用包
```

## 使用方法

1. 首次启动时，授予**辅助功能权限**（用于控制网易云音乐）
2. 打开网易云音乐并播放音乐
3. 应用会在后台自动工作
4. 点击菜单栏图标可以查看当前状态

### 菜单栏图标说明

| 图标 | 状态 |
|------|------|
| 🎵 | 网易云音乐播放中 |
| ⏸ | 网易云音乐已暂停 |
| 🔊 | 检测到其他应用播放中 |

## 工作原理

1. 使用 `media-control` 监控系统 **Now Playing** 状态
2. 检测到非网易云应用播放时，通过 **AppleScript** 暂停网易云
3. 检测到其他应用停止播放时，自动恢复网易云

### 6 状态模型

应用内部使用 6 状态有限状态机管理：

| 状态 | NowPlaying | 网易云 | 说明 |
|------|------------|--------|------|
| S1 | 网易云播放 | 播放 | 正常播放 |
| S2 | 网易云暂停 | 暂停 | 正常暂停 |
| S3 | 其他播放 | 播放 | 冲突 → 自动暂停 |
| S4 | 其他播放 | 暂停 | 已暂停 |
| S5 | 其他空闲 | 播放 | 正常播放 |
| S6 | 其他空闲 | 暂停 | 正常暂停 |

## 系统要求

- macOS 13.0+
- 网易云音乐 macOS 版
- `media-control` CLI 工具

## 权限说明

- **辅助功能权限**：用于通过 AppleScript 控制网易云音乐的播放/暂停

## 日志

应用日志保存在 `~/Library/Logs/CloudYield/`，可通过菜单栏的「打开日志目录」查看。

## 许可证

[MIT License](LICENSE)

## 致谢

- [media-control](https://github.com/ungive/media-control) - 用于获取系统 Now Playing 状态
