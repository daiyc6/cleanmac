#!/bin/bash
# 打包发布用的 DMG：cleanmac.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" .build/cleanmac.app/Contents/Info.plist 2>/dev/null || echo "0.1.0")
DMG="dist/cleanmac-${VER}.dmg"
STAGE="$(mktemp -d)"

[ -d .build/cleanmac.app ] || { echo "先运行 bash build.sh"; exit 1; }

echo ">>> 组装 $DMG"
mkdir -p dist
cp -R .build/cleanmac.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 首次打开说明
cat > "$STAGE/如何使用.txt" <<'TXT'
cleanmac —— 免费、开源、不联网的 macOS 空间清理工具

【安装】
把 cleanmac 拖到 Applications 文件夹。

【第一次打开】
这个版本没有做苹果公证（$99/年 的年费），所以系统会提示
"无法打开，因为无法验证开发者"。这是正常的。

两种打开方式，任选其一：
1. 在「应用程序」里右键点击 cleanmac → 选择「打开」→ 再点「打开」
2. 打开「终端」，执行：
   xattr -dr com.apple.quarantine /Applications/cleanmac.app

【建议】
在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中勾选 cleanmac，
否则「下载 / 桌面 / 文稿」里的文件不会被扫描到。

【安全】
所有删除都会先移入隔离区，保留 1 天可还原。
TXT

hdiutil create -volname "cleanmac" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "OK: $DMG  ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | awk '{print "SHA256: " $1}'
