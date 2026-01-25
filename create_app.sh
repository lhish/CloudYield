#!/bin/bash
#
# 创建 macOS .app 应用包
#

set -e

echo "📦 创建 macOS 应用包..."
echo "=========================================="

APP_NAME="CloudYield"
VERSION="1.1.1"
BUILD_NUMBER="3"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"

# 避免 clang 模块缓存写入受限目录（尤其是在沙盒/受限环境中）
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"

# 1. 构建 Release 版本
echo "1️⃣  构建 Release 版本..."
swift build --disable-sandbox -c release

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
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>CloudYield</string>
    <key>CFBundleIdentifier</key>
    <string>com.lhish.cloudyield</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CloudYield</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要控制网易云音乐的播放状态</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>用于检测其他应用是否正在出声，以自动暂停/恢复网易云音乐</string>
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

# 6. 创建 Entitlements 文件
echo "6️⃣  创建 Entitlements..."
cat > "$CONTENTS_DIR/Entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "✅ Entitlements 已创建"
echo ""

# 7. 代码签名（使用固定的 identifier + Hardened Runtime 避免每次重签导致权限丢失）
echo "7️⃣  代码签名..."

# 先移除已有签名
codesign --remove-signature "$APP_DIR" 2>/dev/null || true

# 使用 ad-hoc 签名但保持 identifier 一致，并启用 Hardened Runtime
# 关键：使用 --preserve-metadata 来保持元数据一致性
codesign --force --deep --sign - \
    --identifier "com.lhish.cloudyield" \
    --entitlements "$CONTENTS_DIR/Entitlements.plist" \
    --options runtime \
    --timestamp=none \
    "$APP_DIR"

if [ $? -eq 0 ]; then
    echo "✅ 代码签名完成（Hardened Runtime）"

    # 显示签名信息
    echo ""
    echo "📋 签名信息："
    codesign -dvvv "$APP_DIR" 2>&1 | grep -E "(Identifier|CDHash)" | head -3
else
    echo "⚠️  代码签名失败（不影响使用）"
fi
echo ""

# 8. 完成
echo "=========================================="
echo "✅ 应用包创建完成！"
echo ""
echo "📂 位置: $(pwd)/$APP_DIR"
echo "📊 大小: $(du -sh "$APP_DIR" | cut -f1)"
echo ""

# 8. 打包 zip（用于 GitHub Release 附件）
echo "8️⃣  打包 zip..."
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_NAME"
echo "✅ Zip 已生成: $(pwd)/$ZIP_NAME"
echo "📦 Zip 大小: $(du -sh "$ZIP_NAME" | cut -f1)"
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
echo "  - 权限会授予给 'CloudYield' 应用"
echo "  - 而不是 Terminal"
echo "=========================================="
