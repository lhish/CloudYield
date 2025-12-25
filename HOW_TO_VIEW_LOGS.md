# 📝 查看应用日志的方法

## 问题：双击运行 .app 后看不到日志

当您双击 `StillMusicWhenBack.app` 运行时，日志不会显示在终端。这里有几种方法查看日志：

---

## 方法1：使用 Console.app（最简单）⭐

### 步骤：

1. **打开 Console 应用**
   ```bash
   open -a Console
   ```
   或者在 Spotlight 搜索 "Console"

2. **启动您的应用**
   ```bash
   open StillMusicWhenBack.app
   ```

3. **在 Console 中过滤日志**
   - 在搜索框输入：`StillMusicWhenBack`
   - 或者输入：`[App]` / `[AudioMonitor]` / `[StateEngine]`

4. **实时查看**
   - Console 会实时显示所有日志
   - 可以看到完整的调试信息

### 优点：
- ✅ 图形界面，方便查看
- ✅ 支持实时滚动
- ✅ 支持搜索和过滤
- ✅ 可以保存日志

---

## 方法2：使用 log stream 命令

### 在终端运行：

```bash
# 先启动应用
open StillMusicWhenBack.app

# 然后在另一个终端窗口查看日志
log stream --predicate 'process == "StillMusicWhenBack"' --level debug
```

### 只看关键日志：
```bash
# 只看包含特定标签的日志
log stream --predicate 'process == "StillMusicWhenBack"' --level info | grep -E "\[App\]|\[AudioMonitor\]|\[StateEngine\]"
```

### 优点：
- ✅ 命令行查看
- ✅ 可以保存到文件
- ✅ 支持过滤

---

## 方法3：将日志输出到文件

### 修改启动方式：

创建一个启动脚本 `start_with_log.sh`：

```bash
#!/bin/bash

LOG_FILE="$HOME/Desktop/StillMusicWhenBack.log"

echo "启动 StillMusicWhenBack..."
echo "日志将保存到: $LOG_FILE"

# 清空旧日志（可选）
# > "$LOG_FILE"

# 启动应用并捕获日志
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack >> "$LOG_FILE" 2>&1 &

echo "应用已启动，查看日志："
echo "  tail -f $LOG_FILE"

# 实时显示日志
tail -f "$LOG_FILE"
```

### 使用：
```bash
chmod +x start_with_log.sh
./start_with_log.sh
```

### 优点：
- ✅ 日志保存到桌面，方便查看
- ✅ 可以随时打开文件查看历史日志

---

## 方法4：添加日志文件功能（推荐）✨

我可以修改代码，让应用自动将日志写入文件。这样无论如何启动都能查看日志。

### 实现方式：

在应用中添加一个 `Logger` 类，同时输出到：
1. 控制台（标准输出）
2. 文件（`~/Library/Logs/StillMusicWhenBack/app.log`）

### 使用：
```bash
# 查看日志文件
tail -f ~/Library/Logs/StillMusicWhenBack/app.log

# 或者在 Finder 中打开
open ~/Library/Logs/StillMusicWhenBack/
```

**需要我实现这个功能吗？** 这样您就可以随时查看日志了。

---

## 方法5：查看系统日志（事后分析）

### 查看最近的日志：
```bash
# 查看最近5分钟的日志
log show --predicate 'process == "StillMusicWhenBack"' --last 5m

# 导出到文件
log show --predicate 'process == "StillMusicWhenBack"' --last 1h > logs.txt
```

---

## 🎯 推荐方案

### 日常使用：
**Console.app** - 最简单直观

### 调试时：
**方法4（日志文件）** - 最方便，无需额外操作

### 临时查看：
**log stream** - 快速查看实时日志

---

## 💡 我的建议

让我为应用添加**自动日志文件功能**，这样：
1. ✅ 双击运行也能记录日志
2. ✅ 随时可以查看历史日志
3. ✅ 不影响正常使用
4. ✅ 日志自动轮转（不会占用太多空间）

**要实现吗？** 只需要添加一个简单的 Logger 类即可。
