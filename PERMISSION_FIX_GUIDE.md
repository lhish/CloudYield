# 🎯 正确的权限配置指南

## ❗ 重要说明

您遇到的问题是 **macOS 的安全机制导致的**。

### 问题原因

从**命令行**运行 Swift 可执行文件时：
```bash
./run.sh
# 或
.build/debug/StillMusicWhenBack
```

系统会将权限授予给 **Terminal（终端应用）** 而不是 `StillMusicWhenBack` 本身。

这就是为什么在"屏幕与系统录音"列表中看不到 `StillMusicWhenBack` 的原因。

---

## ✅ 解决方案（2选1）

### 方案1：创建 .app 应用包（推荐）⭐

这是**正确的**方式，权限会授予给应用本身。

#### 步骤：

1. **运行脚本创建应用包**
   ```bash
   ./create_app.sh
   ```

2. **启动应用**
   ```bash
   # 方法1：双击运行（推荐）
   open StillMusicWhenBack.app

   # 方法2：命令行
   open -a StillMusicWhenBack
   ```

3. **授予权限**
   - 系统会弹出权限对话框
   - 点击 **[Allow]** 授予屏幕录制权限
   - 现在列表中会显示 **StillMusicWhenBack** ✅

4. **安装到应用程序文件夹（可选）**
   ```bash
   cp -r StillMusicWhenBack.app /Applications/
   ```

#### 优点：
- ✅ 权限正确授予给应用
- ✅ 可以双击运行
- ✅ 更安全（Terminal 不需要权限）
- ✅ 可以添加到 Dock
- ✅ 支持开机自启动

---

### 方案2：给 Terminal 授予权限（临时方案）

如果您想继续使用命令行方式运行，可以给终端授予权限。

#### 步骤：

1. **找到您使用的终端应用**
   - 系统终端：**Terminal**
   - iTerm2：**iTerm**
   - VSCode 内置终端：**Code** 或 **Visual Studio Code**

2. **在系统设置中授予权限**
   - 打开：系统设置 → 隐私与安全性 → 屏幕与系统录音
   - 勾选您的**终端应用**（如 Terminal、iTerm、Code）

3. **重启终端并运行**
   ```bash
   # 关闭并重新打开终端
   ./run.sh
   ```

#### 缺点：
- ⚠️ 终端获得了屏幕录制权限（安全风险）
- ⚠️ 所有在终端运行的程序都能访问屏幕内容

---

## 📋 对比表格

| 特性 | .app 应用包 | 给 Terminal 权限 |
|------|------------|-----------------|
| 安全性 | ✅ 高 | ⚠️ 低 |
| 权限范围 | ✅ 仅应用 | ⚠️ 整个终端 |
| 用户体验 | ✅ 好（双击运行） | ⚠️ 一般（命令行） |
| 开机自启 | ✅ 支持 | ❌ 不支持 |
| 推荐度 | ⭐⭐⭐⭐⭐ | ⭐⭐ |

---

## 🚀 推荐工作流程

### 一次性设置（推荐）

```bash
# 1. 创建应用包
./create_app.sh

# 2. 复制到 Applications
cp -r StillMusicWhenBack.app /Applications/

# 3. 启动应用（首次会请求权限）
open -a StillMusicWhenBack
```

**之后每次启动：**
```bash
open -a StillMusicWhenBack
```

或者直接从 **Spotlight** 搜索 "StillMusicWhenBack" 并回车。

---

## 🔍 验证权限

### 检查应用是否出现在权限列表中

1. **打开系统设置**
   ```bash
   open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
   ```

2. **查找应用**
   - ✅ 使用 `.app`：会显示 **"StillMusicWhenBack"**
   - ⚠️ 使用命令行：会显示 **"Terminal"** 或其他终端应用

### 通过日志验证

运行应用后查看控制台输出：

**权限已授予：**
```
[App] ✅ 已有屏幕录制权限
[App] ✅ 已有辅助功能权限
[AudioMonitor] ✅ 音频监控已启动
```

**缺少权限：**
```
[App] ⚠️  缺少屏幕录制权限，正在请求...
[App] ⚠️  仍缺少屏幕录制权限，显示设置指引
```

---

## 💡 常见问题

### Q: 为什么从命令行运行看不到应用名称？

**A**: macOS 安全机制。命令行程序的权限由**启动它的终端**承载。只有 `.app` 应用包才有独立的权限身份。

### Q: 我能不能直接给可执行文件授权？

**A**: 不能。macOS 只认 `.app` 应用包。裸的可执行文件必须通过其启动者（如 Terminal）来请求权限。

### Q: 创建 .app 后如何调试？

**A**: 有几种方法：

```bash
# 方法1：查看应用日志
log stream --predicate 'process == "StillMusicWhenBack"' --level debug

# 方法2：从命令行启动（保留控制台输出）
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack

# 方法3：使用 Console.app 查看系统日志
open -a Console
```

### Q: 可以签名吗？

**A**: 可以，但需要 Apple Developer 账号：

```bash
# 签名应用
codesign --force --deep --sign "Developer ID Application: Your Name" StillMusicWhenBack.app

# 验证签名
codesign -dv --verbose=4 StillMusicWhenBack.app
```

---

## 📊 完整对比

### 方式1：直接运行可执行文件
```bash
.build/debug/StillMusicWhenBack
```
- ❌ 权限授予 Terminal
- ❌ 列表中不显示应用
- ❌ 不支持双击运行
- ❌ 不支持 Dock
- ✅ 开发调试方便

### 方式2：使用 .app 应用包
```bash
open StillMusicWhenBack.app
```
- ✅ 权限授予应用本身
- ✅ 列表中正确显示
- ✅ 支持双击运行
- ✅ 支持 Dock 和 Launchpad
- ✅ 支持开机自启动
- ✅ 更符合 macOS 应用规范

---

## ✅ 最终建议

**对于日常使用：**
```bash
./create_app.sh
cp -r StillMusicWhenBack.app /Applications/
open -a StillMusicWhenBack
```

**对于开发调试：**
```bash
# 临时给 Terminal 授权
# 或使用 .app 方式配合 log stream
```

---

*更新时间: 2025-12-25*
*版本: 1.2.0 - 应用包支持*
