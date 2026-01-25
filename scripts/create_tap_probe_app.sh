#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_SRC="${ROOT_DIR}/scripts/process_tap_probe.swift"

APP_NAME="TapProbe"
BUILD_DIR="${ROOT_DIR}/.build/tap-probe"
BIN_PATH="${BUILD_DIR}/${APP_NAME}"
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ ! -f "${PROBE_SRC}" ]]; then
  echo "ERROR: missing probe source: ${PROBE_SRC}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

echo "1) 编译探针可执行文件..."
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
  -O \
  -sdk "${SDKROOT}" \
  -Xcc -fmodules-cache-path=/tmp/clang-module-cache \
  -module-cache-path /tmp/swift-module-cache \
  "${PROBE_SRC}" \
  -o "${BIN_PATH}"

echo "2) 打包 ${APP_NAME}.app（用于提供 NSAudioCaptureUsageDescription 并以 App 身份运行）..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>TapProbe</string>
  <key>CFBundleIdentifier</key>
  <string>com.lhish.cloudyield.tapprobe</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TapProbe</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAudioCaptureUsageDescription</key>
  <string>用于检测“其他应用是否正在出声”，以验证 Process Tap 方案的可行性。</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "3) 代码签名（ad-hoc，便于触发权限/落库到 TCC）..."
codesign --remove-signature "${APP_DIR}" 2>/dev/null || true
codesign --force --deep --sign - \
  --identifier "com.lhish.cloudyield.tapprobe" \
  --options runtime \
  --timestamp=none \
  "${APP_DIR}" || true

echo ""
echo "✅ 完成：${APP_DIR}"
echo ""
echo "建议运行方式（更容易正确触发/归属 Audio Capture 权限）："
echo "  open -n ${APP_DIR} --args --duration=10 --interval=0.1 --out=/tmp/tapprobe.jsonl"
echo ""
echo "（可选）权限已授予后，想直接看 stdout 也可以："
echo "  ${APP_DIR}/Contents/MacOS/${APP_NAME} --duration=10 --interval=0.1"
echo ""
echo "如果你之前点过拒绝，需要在：系统设置 → 隐私与安全性 → 音频捕获（Audio Capture）里手动允许。"
