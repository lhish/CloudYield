#!/bin/bash
#
# StillMusicWhenBack - 快速运行脚本
#

echo "🎵 StillMusicWhenBack - 智能音乐助手"
echo "=========================================="
echo ""

# 检查构建产物是否存在
if [ ! -f ".build/debug/StillMusicWhenBack" ]; then
    echo "⚠️  未找到可执行文件，正在构建..."
    swift build

    if [ $? -ne 0 ]; then
        echo "❌ 构建失败，请检查错误信息"
        exit 1
    fi
    echo ""
fi

echo "✅ 准备启动应用..."
echo ""
echo "💡 提示："
echo "  - 首次运行需要授予系统权限"
echo "  - 屏幕录制权限：用于监控系统音频"
echo "  - 辅助功能权限：用于控制网易云音乐"
echo "  - 使用 Ctrl+C 停止应用"
echo ""
echo "📊 应用将在 3 秒后启动..."
sleep 3

echo "=========================================="
echo ""

# 运行应用
exec .build/debug/StillMusicWhenBack
