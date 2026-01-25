# CloudYield

🎵 让网易云音乐更智能 - 当其他应用播放音频时自动暂停网易云，停止后自动恢复。

## 功能特性

- 🔊 检测到其他应用播放音频时**自动暂停**网易云音乐
- ▶️ 其他应用停止播放并保持 **2 秒静音**后**自动恢复**网易云音乐
- ⚡ 暂停触发 **0.02 秒**级别，恢复更稳不抖
- 🖥️ 菜单栏应用，后台静默运行
- 🚀 支持开机自启

## 使用场景

- 看 B 站视频时自动暂停音乐，关闭视频后自动恢复
- 开会时打开腾讯会议/Zoom 自动暂停音乐
- 玩游戏时自动暂停背景音乐
- 任何需要临时暂停音乐的场景

## 安装

### Homebrew（推荐）

```bash
brew tap lhish/cloudyield
brew install --cask cloudyield
```

### 手动下载

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

1. 使用 CoreAudio **Process Tap** 检测“除网易云外是否有其他应用正在出声”（需要授予 **音频捕获** 权限）
2. 检测到其他应用出声时，通过 **AppleScript** 暂停网易云；停止出声后自动恢复

### 状态模型

应用内部使用有限状态机管理（核心维度：其他应用是否出声 + 网易云是否播放）：

| 其他应用出声 | 网易云 | 说明 |
|-------------|--------|------|
| 否 | 播放 | 正常播放 |
| 否 | 暂停 | 正常暂停 |
| 是 | 播放 | 冲突 → 自动暂停 |
| 是 | 暂停 | 已暂停 |

## 系统要求

- macOS 14.2+
- 网易云音乐 macOS 版

## 权限说明

- **辅助功能权限**：用于通过 AppleScript 控制网易云音乐的播放/暂停
- **音频捕获权限**：用于检测其他应用是否出声（Process Tap）

## 日志

应用日志保存在 `~/Library/Logs/CloudYield/`，可通过菜单栏的「打开日志目录」查看。

## 许可证

[GPL-3.0 License](LICENSE)

## 致谢

- [AudioCap](https://github.com/insidegui/AudioCap) - Process Tap API 实践参考
