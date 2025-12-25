#!/bin/bash
#
# 重置TCC权限 - 用于开发阶段每次重新编译后重新授权
#

echo "🔄 重置 StillMusicWhenBack 的TCC权限..."
echo "=========================================="

# 重置屏幕录制权限
echo "1️⃣  重置屏幕录制权限..."
tccutil reset ScreenCapture com.yourdomain.stillmusicwhenback 2>/dev/null
echo "✅ 屏幕录制权限已重置"
echo ""

# 重置辅助功能权限
echo "2️⃣  重置辅助功能权限..."
tccutil reset Accessibility com.yourdomain.stillmusicwhenback 2>/dev/null
echo "✅ 辅助功能权限已重置"
echo ""

# 杀掉运行中的应用
echo "3️⃣  停止运行中的应用..."
pkill -9 StillMusicWhenBack 2>/dev/null || true
sleep 1
echo "✅ 应用已停止"
echo ""

echo "=========================================="
echo "✅ 权限重置完成！"
echo ""
echo "🚀 下一步："
echo "   1. 运行: open -a StillMusicWhenBack"
echo "   2. 在弹出的权限对话框中点击"允许""
echo "   3. 或者手动打开系统设置授予权限"
echo "=========================================="
