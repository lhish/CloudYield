#!/bin/bash
#
# 测试自动日志功能
#

echo "=================================================="
echo "🧪 自动日志功能测试"
echo "=================================================="
echo ""

# 1. 检查应用是否存在
if [ ! -f "StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack" ]; then
    echo "❌ 应用不存在，请先运行 ./create_app.sh"
    exit 1
fi

echo "✅ 应用已存在"
echo ""

# 2. 检查日志目录
LOG_DIR="$HOME/Library/Logs/StillMusicWhenBack"
echo "📂 日志目录: $LOG_DIR"

if [ -d "$LOG_DIR" ]; then
    echo "✅ 日志目录已存在"
    echo ""
    echo "📋 现有日志文件："
    ls -lh "$LOG_DIR"
else
    echo "⚠️  日志目录尚未创建（将在首次运行时创建）"
fi

echo ""
echo "=================================================="
echo "🚀 启动应用测试（5秒后自动停止）"
echo "=================================================="
echo ""

# 3. 启动应用（后台运行）
echo "启动应用..."
./StillMusicWhenBack.app/Contents/MacOS/StillMusicWhenBack &
APP_PID=$!

echo "应用 PID: $APP_PID"
echo ""
echo "等待 5 秒..."
sleep 5

# 4. 停止应用
echo ""
echo "停止应用..."
kill $APP_PID
sleep 1

echo ""
echo "=================================================="
echo "📊 日志检查"
echo "=================================================="
echo ""

# 5. 检查日志文件
if [ -f "$LOG_DIR/app.log" ]; then
    echo "✅ 日志文件已创建"
    echo ""
    echo "📄 日志文件大小:"
    ls -lh "$LOG_DIR/app.log" | awk '{print "  ", $5, $9}'
    echo ""

    echo "📝 最近 20 条日志:"
    echo "=================================================="
    tail -20 "$LOG_DIR/app.log"
    echo "=================================================="
    echo ""

    echo "🔍 日志统计:"
    echo "  DEBUG 日志: $(grep -c 'DEBUG' "$LOG_DIR/app.log" || echo 0)"
    echo "  INFO 日志:  $(grep -c 'INFO' "$LOG_DIR/app.log" || echo 0)"
    echo "  SUCCESS 日志: $(grep -c 'SUCCESS' "$LOG_DIR/app.log" || echo 0)"
    echo "  WARNING 日志: $(grep -c 'WARNING' "$LOG_DIR/app.log" || echo 0)"
    echo "  ERROR 日志: $(grep -c 'ERROR' "$LOG_DIR/app.log" || echo 0)"
    echo ""

    echo "✅ 自动日志功能正常工作！"
else
    echo "❌ 日志文件未创建"
    exit 1
fi

echo ""
echo "=================================================="
echo "💡 实用命令"
echo "=================================================="
echo ""
echo "1. 实时查看日志:"
echo "   tail -f $LOG_DIR/app.log"
echo ""
echo "2. 打开日志目录:"
echo "   open $LOG_DIR"
echo ""
echo "3. 查看所有日志:"
echo "   cat $LOG_DIR/app.log*"
echo ""
echo "4. 搜索错误:"
echo "   grep 'ERROR' $LOG_DIR/app.log"
echo ""
echo "5. 清空日志:"
echo "   rm -f $LOG_DIR/app.log*"
echo ""
