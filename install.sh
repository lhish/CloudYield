#!/bin/bash
#
# 安装 CloudYield 到 /Applications/
#

set -e

APP_NAME="CloudYield"
SOURCE_APP="./$APP_NAME.app"
TARGET_APP="/Applications/$APP_NAME.app"

echo "📦 安装 $APP_NAME 到 /Applications/"
echo "=========================================="

# 检查源应用是否存在
if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ 找不到 $SOURCE_APP"
    echo "请先运行 ./create_app.sh 构建应用"
    exit 1
fi

# 删除旧版本（如果存在）
if [ -d "$TARGET_APP" ]; then
    echo "🗑️  删除旧版本..."
    rm -rf "$TARGET_APP"
fi

# 复制到 /Applications/
echo "📂 复制应用到 /Applications/..."
cp -r "$SOURCE_APP" "$TARGET_APP"

echo ""
echo "✅ 安装完成！"
echo ""
echo "=========================================="
echo "🚀 启动方法:"
echo ""
echo "   open -a $APP_NAME"
echo ""
echo "或双击 /Applications/$APP_NAME.app"
echo "=========================================="
