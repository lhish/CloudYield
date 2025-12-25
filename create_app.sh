#!/bin/bash
#
# 创建 macOS .app 应用包
#

set -e

echo "📦 创建 macOS 应用包..."
echo "=========================================="

APP_NAME="StillMusicWhenBack"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 1. 构建 Release 版本
echo "1️⃣  构建 Release 版本..."
swift build -c release

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "❌ 构建失败，找不到可执行文件"
    exit 1
fi

echo "✅ 构建完成"
echo ""

# 2. 创建应用包目录结构
echo "2️⃣  创建应用包结构..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "✅ 目录结构已创建"
echo ""

# 3. 复制可执行文件
echo "3️⃣  复制可执行文件..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "✅ 可执行文件已复制"
echo ""

# 4. 创建 Info.plist
echo "4️⃣  创建 Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>StillMusicWhenBack</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourdomain.stillmusicwhenback</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StillMusicWhenBack</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>需要访问音频以监控系统声音</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要控制网易云音乐的播放状态</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Info.plist 已创建"
echo ""

# 5. 创建 PkgInfo
echo "5️⃣  创建 PkgInfo..."
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ PkgInfo 已创建"
echo ""

# 6. 完成
echo "=========================================="
echo "✅ 应用包创建完成！"
echo ""
echo "📂 位置: $(pwd)/$APP_DIR"
echo "📊 大小: $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "=========================================="
echo "🚀 使用方法："
echo ""
echo "方法1: 双击运行"
echo "   open $APP_DIR"
echo ""
echo "方法2: 复制到应用程序文件夹"
echo "   cp -r $APP_DIR /Applications/"
echo "   open -a $APP_NAME"
echo ""
echo "方法3: 命令行启动"
echo "   ./$APP_DIR/Contents/MacOS/$APP_NAME"
echo ""
echo "=========================================="
echo "💡 提示："
echo "  - 首次运行会自动请求权限"
echo "  - 权限会授予给 'StillMusicWhenBack' 应用"
echo "  - 而不是 Terminal"
echo "=========================================="
