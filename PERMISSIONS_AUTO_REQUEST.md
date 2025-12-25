# 权限自动请求说明

## ✅ 已实现自动权限请求

应用现在会在启动时**自动检测并请求**所需的系统权限！

---

## 🔄 工作流程

### 启动时的权限检测流程

```
应用启动
  ↓
检查屏幕录制权限
  ├─ ✅ 已有权限 → 继续
  └─ ❌ 缺少权限
      ↓
   自动调用系统权限请求 API
      ↓
   系统弹出权限对话框 ⚡
      ├─ 用户点击"允许" → ✅ 权限授予
      └─ 用户点击"拒绝" → 显示手动设置指引
  ↓
检查辅助功能权限
  ├─ ✅ 已有权限 → 继续
  └─ ❌ 缺少权限
      ↓
   自动调用系统权限请求 API
      ↓
   系统弹出权限对话框 ⚡
      ├─ 用户点击"打开系统设置" → 跳转到设置页面
      └─ 用户点击"拒绝" → 显示控制台提示
  ↓
启动核心服务
```

---

## 📱 首次运行体验

### 场景1：完全首次运行

1. **运行应用**
   ```bash
   ./run.sh
   # 或
   .build/debug/StillMusicWhenBack
   ```

2. **系统自动弹出对话框**

   **第一个对话框 - 屏幕录制权限**
   ```
   ┌────────────────────────────────────────┐
   │ "StillMusicWhenBack" would like to     │
   │ record this screen.                     │
   │                                         │
   │ [ Deny ]              [ Allow ]         │
   └────────────────────────────────────────┘
   ```

   👉 **点击 "Allow"**

3. **控制台输出**
   ```
   [App] 应用启动...
   [App] ⚠️  缺少屏幕录制权限，正在请求...
   [App] ✅ 屏幕录制权限已授予
   ```

4. **第二个对话框 - 辅助功能权限**
   ```
   ┌────────────────────────────────────────┐
   │ "StillMusicWhenBack" would like to     │
   │ control this computer using            │
   │ accessibility features.                │
   │                                         │
   │ [ Deny ]    [ Open System Settings ]   │
   └────────────────────────────────────────┘
   ```

   👉 **点击 "Open System Settings"**

   在打开的系统设置中勾选 **StillMusicWhenBack**

5. **重启应用**
   ```bash
   # Ctrl+C 停止应用
   ./run.sh  # 再次运行
   ```

6. **全部就绪！**
   ```
   [App] ✅ 已有屏幕录制权限
   [App] ✅ 已有辅助功能权限
   [AudioMonitor] ✅ 音频监控已启动
   [StateEngine] ✅ 状态引擎已启动
   ```

---

### 场景2：已有部分权限

如果之前已经授予了某些权限，应用只会请求缺少的权限。

**示例：已有屏幕录制权限**
```
[App] ✅ 已有屏幕录制权限
[App] ⚠️  缺少辅助功能权限，正在请求...
（系统弹出辅助功能权限对话框）
```

---

## 🛠️ 技术实现

### 屏幕录制权限

```swift
// 检查权限
if !permissionManager.hasScreenRecordingPermission() {
    // 自动请求（触发系统对话框）
    permissionManager.requestScreenRecordingPermission()
    // ↑ 调用 CGRequestScreenCaptureAccess()

    // 等待1秒让系统处理
    try? await Task.sleep(nanoseconds: 1_000_000_000)

    // 再次检查
    if !permissionManager.hasScreenRecordingPermission() {
        // 如果仍未授予，显示手动设置指引
        await showPermissionAlert()
    }
}
```

### 辅助功能权限

```swift
// 检查权限
if !permissionManager.hasAccessibilityPermission() {
    // 自动请求（触发系统对话框）
    permissionManager.requestAccessibilityPermission()
    // ↑ 调用 AXIsProcessTrustedWithOptions()

    // 等待0.5秒让系统处理
    try? await Task.sleep(nanoseconds: 500_000_000)
}
```

---

## 💡 常见问题

### Q1: 为什么有时需要重启应用？

**A**: macOS 的某些权限（特别是辅助功能）在授予后需要重启应用才能生效。这是系统限制。

### Q2: 可以跳过权限请求吗？

**A**: 不建议。应用的核心功能依赖这些权限：
- **屏幕录制** → 监控系统音频（必需）
- **辅助功能** → 控制网易云音乐（必需）

没有这些权限，应用无法正常工作。

### Q3: 如果不小心拒绝了权限怎么办？

**A**: 可以手动在系统设置中授予：

```bash
# 方法1：通过命令打开系统设置
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

# 方法2：手动导航
系统设置 → 隐私与安全性 → 屏幕录制 → 勾选 StillMusicWhenBack
```

### Q4: 为什么控制台显示"请在系统设置中授予辅助功能权限"？

**A**: 辅助功能权限的对话框只提供"打开系统设置"选项，不能直接授予。需要：
1. 点击对话框中的"打开系统设置"
2. 在设置页面勾选应用
3. 重启应用

---

## 🎯 最佳实践

### 首次运行建议流程

1. **在安静环境中运行**（用于学习噪音基线）
2. **准备好点击"允许"按钮**（权限对话框会自动弹出）
3. **按照对话框提示操作**
4. **如果需要，重启应用**
5. **测试功能**（播放网易云 + 播放视频）

### 运行前检查清单

- ✅ macOS 版本 ≥ 13.0
- ✅ 网易云音乐已安装
- ✅ 网易云音乐正在运行并播放音乐
- ✅ 环境相对安静（首次运行时）

---

## 📊 权限状态查看

应用启动时会在控制台显示完整的权限状态：

```
[App] 应用启动...
[App] ✅ 已有屏幕录制权限
[App] ✅ 已有辅助功能权限
[AudioMonitor] 正在启动音频监控...
[AudioDetector] 开始学习环境噪音基线（10秒）...
...
```

如果看到 ⚠️  警告，说明缺少某些权限。

---

## 🔧 故障排除

### 问题：对话框没有弹出

**原因**：可能已经有权限，或者之前拒绝过

**解决**：
```bash
# 检查权限状态（查看控制台输出）
./run.sh

# 手动重置权限（需要重新授予）
tccutil reset ScreenCapture com.yourdomain.stillmusicwhenback
tccutil reset Accessibility com.yourdomain.stillmusicwhenback
```

### 问题：授予权限后仍然不工作

**解决**：重启应用
```bash
# Ctrl+C 停止
^C

# 再次运行
./run.sh
```

---

## ✨ 总结

现在应用会**自动处理权限请求**，您只需要：

1. ✅ 运行应用
2. ✅ 在弹出的对话框中点击"允许"或"打开系统设置"
3. ✅ 如果需要，重启应用

**就这么简单！** 🎉

无需手动打开系统设置或查找权限选项（除非您拒绝了自动请求）。

---

*更新时间: 2025-12-25*
*版本: 1.1.0 - 自动权限请求*
