#!/bin/bash
#
# 自动创建 Xcode 项目脚本
# 使用 xcodegen 或 Swift Package Manager 创建项目
#

set -e  # 遇到错误立即退出

echo "🚀 StillMusicWhenBack - 自动项目构建脚本"
echo "=========================================="
echo ""

# 项目配置
PROJECT_NAME="StillMusicWhenBack"
BUNDLE_ID="com.yourdomain.stillmusicwhenback"
PROJECT_DIR="/Users/lhy/CLionProjects/still_music_when_back"

cd "$PROJECT_DIR"

echo "📂 当前目录: $(pwd)"
echo ""

# 方案1: 使用 Swift Package Manager (推荐)
echo "📦 方案1: 使用 Swift Package Manager..."
echo ""

# 创建 Package.swift
cat > Package.swift << 'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StillMusicWhenBack",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "StillMusicWhenBack",
            targets: ["StillMusicWhenBack"]
        )
    ],
    targets: [
        .executableTarget(
            name: "StillMusicWhenBack",
            path: "Sources"
        )
    ]
)
PKGEOF

echo "✅ Package.swift 已创建"
echo ""

# 创建 Sources 目录结构
echo "📁 创建目录结构..."
mkdir -p Sources/App
mkdir -p Sources/Core/AudioMonitor
mkdir -p Sources/Core/MusicController
mkdir -p Sources/Core/StateManager
mkdir -p Sources/Core/Timer
mkdir -p Sources/UI/MenuBar
mkdir -p Sources/Utilities
mkdir -p Sources/Resources

echo "✅ 目录结构已创建"
echo ""

# 复制源文件
echo "📋 复制源代码文件..."

cp SourceFiles/App/StillMusicWhenBackApp.swift Sources/App/
cp SourceFiles/Core/AudioMonitor/*.swift Sources/Core/AudioMonitor/
cp SourceFiles/Core/MusicController/*.swift Sources/Core/MusicController/
cp SourceFiles/Core/StateManager/*.swift Sources/Core/StateManager/
cp SourceFiles/Core/Timer/*.swift Sources/Core/Timer/
cp SourceFiles/UI/MenuBar/*.swift Sources/UI/MenuBar/
cp SourceFiles/Utilities/*.swift Sources/Utilities/

echo "✅ 源文件复制完成"
echo ""

# 创建 Info.plist
echo "📄 创建 Info.plist..."
cat > Sources/Resources/Info.plist << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
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
</dict>
</plist>
PLISTEOF

echo "✅ Info.plist 已创建"
echo ""

echo "=========================================="
echo "✅ Swift Package 项目创建完成！"
echo ""
echo "下一步操作："
echo "1. 打开 Xcode: open Package.swift"
echo "2. 或使用命令行构建: swift build"
echo "3. 或生成 Xcode 项目: swift package generate-xcodeproj"
echo ""
echo "=========================================="
