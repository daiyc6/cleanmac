#!/bin/bash
# 构建 cleanmac.app：universal 二进制 + 图标 + 完整 Info.plist + ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/mcache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.build/mcache"
mkdir -p .build/mcache

CONFIG="${1:-release}"
CACHE="$PWD/.build/mcache"
APP=".build/cleanmac.app"

echo ">>> 编译 (${CONFIG}, universal)"
swift build -c "$CONFIG" \
  --arch arm64 --arch x86_64 \
  --scratch-path .build \
  --cache-path .build/cache \
  -Xswiftc -module-cache-path -Xswiftc "$CACHE" 2>&1 | grep -v "^\[" | tail -20

BIN=".build/out/Products/Release/cleanmac"
[ -f "$BIN" ] || BIN=".build/${CONFIG}/cleanmac"
[ -f "$BIN" ] || { echo "ERROR: 找不到产物"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/cleanmac"

cp design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>cleanmac</string>
  <key>CFBundleDisplayName</key><string>cleanmac</string>
  <key>CFBundleIdentifier</key><string>com.cleanmac.app</string>
  <key>CFBundleExecutable</key><string>cleanmac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License · 免费开源</string>
  <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "OK: $APP"
echo "   架构: $(lipo -archs "$APP/Contents/MacOS/cleanmac" 2>/dev/null || echo '?')"
echo "   运行: open $APP"
