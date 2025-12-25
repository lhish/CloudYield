# StillMusicWhenBack - 项目设置指南

## 第一步：创建 Xcode 项目

1. 打开 Xcode
2. 选择 **File → New → Project**
3. 在模板选择界面：
   - 选择 **macOS** 标签
   - 选择 **App** 模板
   - 点击 **Next**

4. 项目配置：
   - **Product Name**: `StillMusicWhenBack`
   - **Team**: 选择您的开发团队（或选择 None）
   - **Organization Identifier**: `com.yourdomain`（请替换为您自己的标识符）
   - **Bundle Identifier**: 将自动生成为 `com.yourdomain.StillMusicWhenBack`
   - **Interface**: 选择 **SwiftUI**
   - **Language**: 选择 **Swift**
   - **取消勾选** Use Core Data
   - **取消勾选** Include Tests

5. 保存位置：
   - 选择 `/Users/lhy/CLionProjects/still_music_when_back/` 作为保存位置
   - **勾选** Create Git repository on my Mac
   - 点击 **Create**

## 第二步：配置项目设置

### 2.1 设置最低系统版本

1. 在项目导航器中选择项目文件（蓝色图标）
2. 选择 **TARGETS** 下的 **StillMusicWhenBack**
3. 在 **General** 标签页中：
   - **Minimum Deployments**: 设置为 **macOS 13.0**

### 2.2 配置 Signing & Capabilities

1. 选择 **Signing & Capabilities** 标签页
2. 点击 **+ Capability** 按钮，添加以下权限：
   - **App Sandbox**（如果未自动添加）
   - 在 App Sandbox 中勾选：
     - ✅ **Outgoing Connections (Client)**
     - ✅ **Audio Input**（用于音频监控）
     - ✅ **Apple Events**（用于控制网易云音乐）

### 2.3 配置 Info.plist

1. 在项目导航器中找到 `Info.plist` 文件
2. 右键点击 `Info` 文件，选择 **Open As → Source Code**
3. 在 `<dict>` 标签内添加以下权限描述：

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

### 2.4 禁用 App Sandbox（可选，用于开发）

如果在开发过程中遇到权限问题，可以临时禁用 App Sandbox：
1. 在 **Signing & Capabilities** 标签页
2. 找到 **App Sandbox**
3. 点击右侧的 **-** 按钮移除

**注意**：发布到 Mac App Store 时需要重新启用并配置正确的权限。

## 第三步：添加源代码文件

项目创建完成后，请按照以下步骤添加源代码文件：

1. 删除自动生成的 `ContentView.swift`（我们不需要它）
2. 创建以下目录结构（在 Xcode 项目导航器中右键 → New Group）：
   ```
   StillMusicWhenBack/
   ├── App/
   ├── Core/
   │   ├── AudioMonitor/
   │   ├── MusicController/
   │   ├── StateManager/
   │   └── Timer/
   ├── UI/
   │   └── MenuBar/
   ├── Models/
   ├── Utilities/
   └── Resources/
   ```

3. 将我为您准备的 Swift 文件添加到对应的目录中

## 第四步：配置 Hardened Runtime

1. 选择 **Build Settings** 标签页
2. 搜索 **Hardened Runtime**
3. 确保 **Enable Hardened Runtime** 设置为 **Yes**
4. 搜索 **Runtime Exceptions**，添加以下异常（如果需要）：
   - **Allow Apple Events** (com.apple.security.automation.apple-events)

## 第五步：构建和运行

1. 选择运行目标为 **My Mac**
2. 点击 **Run** 按钮（⌘+R）
3. 首次运行时，系统会提示您授予以下权限：
   - **辅助功能权限**（Accessibility）
   - **屏幕录制权限**（Screen Recording）
   - **Apple Events 权限**

4. 前往 **系统设置 → 隐私与安全性** 授予相应权限

## 常见问题

### Q: ScreenCaptureKit 找不到？
A: 确保您的 macOS 版本 ≥ 13.0，并且 Xcode 版本 ≥ 15.0

### Q: 无法访问系统音频？
A: 需要授予 **Screen Recording** 权限，前往系统设置授予权限后重启应用

### Q: 无法控制网易云音乐？
A: 需要授予 **Accessibility** 权限，同时确保网易云音乐正在运行

### Q: 应用无法开机自启动？
A: macOS 13+ 使用 ServiceManagement 框架，首次需要用户同意

## 下一步

项目设置完成后，您可以：
1. 运行应用测试功能
2. 在菜单栏查看应用图标
3. 播放网易云音乐并测试自动暂停/恢复功能
4. 查看日志输出调试问题

如有任何问题，请参考 `README.md` 或查看源代码注释。
