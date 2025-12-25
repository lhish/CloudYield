# 📝 自动日志文件功能说明

## ✅ 已实现自动日志到文件

应用现在会自动将所有日志同时输出到：
1. **控制台**（标准输出）- 用于实时查看
2. **日志文件** - 用于历史查看和调试

---

## 📂 日志文件位置

### 日志目录
```
~/Library/Logs/StillMusicWhenBack/
```

### 日志文件
```
app.log         # 当前日志文件
app.log.1       # 归档日志文件（最近的）
app.log.2       # 归档日志文件
app.log.3       # 归档日志文件
app.log.4       # 归档日志文件
app.log.5       # 归档日志文件（最旧的）
```

---

## 🚀 快速查看日志

### 方法1：打开日志目录（推荐）⭐
```bash
open ~/Library/Logs/StillMusicWhenBack/
```

直接在 Finder 中查看和打开日志文件。

### 方法2：实时查看日志
```bash
tail -f ~/Library/Logs/StillMusicWhenBack/app.log
```

### 方法3：查看所有历史日志
```bash
cat ~/Library/Logs/StillMusicWhenBack/app.log*
```

### 方法4：搜索特定关键词
```bash
# 搜索错误
grep "ERROR" ~/Library/Logs/StillMusicWhenBack/app.log

# 搜索成功消息
grep "SUCCESS" ~/Library/Logs/StillMusicWhenBack/app.log

# 搜索特定模块
grep "\[AudioMonitor\]" ~/Library/Logs/StillMusicWhenBack/app.log
```

---

## 📊 日志格式

每条日志包含：
- **时间戳**（精确到毫秒）
- **日志级别**（DEBUG/INFO/WARNING/ERROR/SUCCESS）
- **模块标识**
- **日志内容**

### 示例输出
```
[2025-12-25 14:30:15.234] ℹ️ INFO [App] 应用启动...
[2025-12-25 14:30:15.345] ℹ️ INFO [App] 日志文件位置: /Users/lhy/Library/Logs/StillMusicWhenBack/app.log
[2025-12-25 14:30:15.456] ✅ SUCCESS [App] 已有屏幕录制权限
[2025-12-25 14:30:15.567] ✅ SUCCESS [App] 已有辅助功能权限
[2025-12-25 14:30:16.123] 🔧 DEBUG [AudioMonitor] 正在启动音频监控...
[2025-12-25 14:30:16.234] 🔧 DEBUG [AudioMonitor] 找到 1 个显示器
[2025-12-25 14:30:16.345] ✅ SUCCESS [AudioMonitor] 音频监控已启动成功！
[2025-12-25 14:30:16.456] ℹ️ INFO [AudioDetector] 开始学习环境噪音基线（10秒）...
[2025-12-25 14:30:26.567] ✅ SUCCESS [AudioDetector] 基线学习完成: -45.2 dB
```

---

## 🔄 自动日志轮转

### 工作原理
- 当 `app.log` 达到 **10 MB** 时，自动轮转
- 旧日志文件会自动重命名为 `app.log.1`, `app.log.2` 等
- 最多保留 **5 个历史日志文件**
- 最旧的日志会被自动删除

### 轮转示例
```
app.log (9.8 MB) → 写入到 10 MB
                 ↓
app.log (新文件) ← 创建
app.log.1 (10 MB) ← 原 app.log 重命名
app.log.2 (10 MB)
app.log.3 (10 MB)
app.log.4 (10 MB)
app.log.5 (10 MB) ← 即将被删除
```

---

## 🎯 应用启动时的日志输出

### 控制台输出
应用启动时会在控制台显示日志文件位置：
```
[2025-12-25 14:30:15.345] ℹ️ INFO [App] 日志文件位置: /Users/lhy/Library/Logs/StillMusicWhenBack/app.log
```

### 查看方式

**从命令行运行：**
```bash
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack
```
- ✅ 控制台有输出
- ✅ 日志文件有记录

**双击运行 .app：**
```bash
open StillMusicWhenBack.app
```
- ❌ 控制台无输出（没有连接终端）
- ✅ 日志文件有完整记录

---

## 🛠️ 日志管理

### 清空所有日志（如需要）
```bash
rm -f ~/Library/Logs/StillMusicWhenBack/app.log*
```

应用会在下次启动时自动创建新的日志文件。

### 导出日志（用于问题报告）
```bash
# 压缩所有日志文件
cd ~/Library/Logs/StillMusicWhenBack/
tar -czf ~/Desktop/stillmusic_logs.tar.gz app.log*

# 现在可以发送 ~/Desktop/stillmusic_logs.tar.gz
```

---

## 📋 日志级别说明

| 级别 | 标记 | 说明 | 示例场景 |
|------|------|------|----------|
| **DEBUG** | 🔧 DEBUG | 详细的调试信息 | 音频缓冲区处理、权限检查详情 |
| **INFO** | ℹ️ INFO | 一般信息 | 应用启动、状态变化 |
| **SUCCESS** | ✅ SUCCESS | 成功操作 | 权限授予、服务启动成功 |
| **WARNING** | ⚠️ WARNING | 警告信息 | 网易云未运行、操作失败但有备用方案 |
| **ERROR** | ❌ ERROR | 错误信息 | 启动失败、AppleScript 错误 |

---

## 🔍 调试技巧

### 问题诊断流程

1. **启动应用**（任何方式）
2. **查看日志文件**
   ```bash
   tail -f ~/Library/Logs/StillMusicWhenBack/app.log
   ```
3. **重现问题**（播放视频、暂停网易云等）
4. **查看日志中的错误**
   ```bash
   grep "ERROR\|WARNING" ~/Library/Logs/StillMusicWhenBack/app.log
   ```

### 常见问题日志示例

**问题1：没有找到显示器**
```
[AudioMonitor] ❌ ERROR 没有找到可用的显示器！
```
→ 缺少屏幕录制权限

**问题2：网易云控制失败**
```
[MusicController] ⚠️ WARNING 暂停失败，尝试备用方案...
[MusicController] ⚠️ WARNING 网易云音乐未运行
```
→ 网易云未启动或缺少辅助功能权限

**问题3：收不到音频缓冲区**
```
[AudioMonitor] ✅ SUCCESS 音频监控已启动成功！
（之后没有 "收到音频缓冲区" 的日志）
```
→ 系统音频流问题，可能需要重启应用

---

## ✨ 优势

与之前的 `print` 输出相比：

| 特性 | print | Logger |
|------|-------|--------|
| **持久化** | ❌ 控制台关闭即丢失 | ✅ 自动保存到文件 |
| **历史查看** | ❌ 无法查看历史 | ✅ 保留最近 50MB 日志 |
| **双击运行** | ❌ 看不到输出 | ✅ 照常记录 |
| **搜索过滤** | ❌ 困难 | ✅ 支持 grep 等工具 |
| **时间戳** | ❌ 无 | ✅ 精确到毫秒 |
| **模块标识** | ✅ 手动添加 | ✅ 自动添加 |
| **自动轮转** | ❌ 无 | ✅ 自动管理大小 |

---

## 💡 实用场景

### 场景1：用户报告问题
用户可以直接发送日志文件：
```bash
open ~/Library/Logs/StillMusicWhenBack/
```
→ 找到 `app.log` → 发送给开发者

### 场景2：开机自启动调试
应用开机自启动后，无法看到终端输出：
```bash
# 等待应用启动后查看日志
tail -n 50 ~/Library/Logs/StillMusicWhenBack/app.log
```

### 场景3：长时间运行监控
应用运行几天后，查看是否有异常：
```bash
# 查看所有错误
grep "ERROR" ~/Library/Logs/StillMusicWhenBack/app.log*

# 查看是否有权限问题
grep "权限" ~/Library/Logs/StillMusicWhenBack/app.log*
```

---

## 📝 技术实现

### Logger 类位置
```
Sources/Utilities/Logger.swift
```

### 核心特性
- **线程安全**：使用 DispatchQueue 串行队列
- **自动轮转**：文件达到 10MB 时自动轮转
- **全局单例**：`Logger.shared`
- **便捷函数**：`logDebug()`, `logInfo()`, `logWarning()`, `logError()`, `logSuccess()`

### 使用示例
```swift
// 在代码中使用
logInfo("应用启动", module: "App")
logDebug("找到 \(count) 个显示器", module: "AudioMonitor")
logError("启动失败: \(error)", module: "AudioMonitor")
logSuccess("权限已授予", module: "App")
logWarning("网易云未运行", module: "MusicController")
```

---

## 🆕 更新说明

**版本**: 1.4.0 - 自动日志文件支持

**更新内容**:
- ✅ 新增 Logger 工具类
- ✅ 所有模块集成日志系统
- ✅ 自动日志文件轮转
- ✅ 保留 5 个历史日志文件（最多 50MB）
- ✅ 启动时显示日志文件路径

**影响**:
- 无论从命令行还是双击运行，都会自动记录日志
- 日志文件位于标准 macOS 日志目录
- 不影响现有控制台输出

---

*更新时间: 2025-12-25*
*版本: 1.4.0 - 自动日志文件功能*
