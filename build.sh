#!/bin/bash
# DSH 启动器构建脚本 —— 在 macOS 上编译、打包、签名
set -euo pipefail
cd "$(dirname "$0")"

APP=".build/DSH 桌面版.app"
BIN=".build/DSHLauncher"

# 新版 CommandLineTools 存在 SwiftBridging 模块重复定义的缺陷
# （usr/include/swift/ 下同时有 module.modulemap 和 bridging.modulemap）。
# 解决办法：拷贝一份 include，删掉冲突的 module.modulemap，再用
# -resource-dir 让编译器使用补丁后的资源目录 —— 全程不动系统文件。
RESDIR_FLAGS=()
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
if [ -f "$CLT_SWIFT_INC/module.modulemap" ] && [ -f "$CLT_SWIFT_INC/bridging.modulemap" ]; then
    echo "==> 检测到 CLT SwiftBridging 冲突，应用编译补丁"
    rm -rf /tmp/dsh-launcher-crt
    mkdir -p /tmp/dsh-launcher-crt/usr/lib /tmp/dsh-launcher-crt/usr/include
    ln -s /Library/Developer/CommandLineTools/usr/lib/swift /tmp/dsh-launcher-crt/usr/lib/swift
    cp -R "$CLT_SWIFT_INC" /tmp/dsh-launcher-crt/usr/include/swift
    rm -f /tmp/dsh-launcher-crt/usr/include/swift/module.modulemap
    RESDIR_FLAGS=(-resource-dir /tmp/dsh-launcher-crt/usr/lib/swift)
fi

echo "==> 清理 build"
rm -rf .build
mkdir -p .build "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 生成图标"
swiftc -parse-as-library -O "${RESDIR_FLAGS[@]}" -o .build/icon-gen tools/IconGen.swift
./.build/icon-gen
mkdir -p .build/AppIcon.iconset
sips -z 16 16   .build/icon-1024.png --out .build/AppIcon.iconset/icon_16x16.png        >/dev/null
sips -z 32 32   .build/icon-1024.png --out .build/AppIcon.iconset/icon_16x16@2x.png     >/dev/null
sips -z 32 32   .build/icon-1024.png --out .build/AppIcon.iconset/icon_32x32.png        >/dev/null
sips -z 64 64   .build/icon-1024.png --out .build/AppIcon.iconset/icon_32x32@2x.png     >/dev/null
sips -z 128 128 .build/icon-1024.png --out .build/AppIcon.iconset/icon_128x128.png      >/dev/null
sips -z 256 256 .build/icon-1024.png --out .build/AppIcon.iconset/icon_128x128@2x.png   >/dev/null
sips -z 256 256 .build/icon-1024.png --out .build/AppIcon.iconset/icon_256x256.png      >/dev/null
sips -z 512 512 .build/icon-1024.png --out .build/AppIcon.iconset/icon_256x256@2x.png   >/dev/null
sips -z 512 512 .build/icon-1024.png --out .build/AppIcon.iconset/icon_512x512.png      >/dev/null
cp .build/icon-1024.png .build/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> 编译主程序"
swiftc -parse-as-library -O -swift-version 5 "${RESDIR_FLAGS[@]}" \
  -framework SwiftUI -framework AppKit -framework WebKit \
  -o "$BIN" Sources/DSHLauncher.swift

echo "==> 组装 .app"
cp "$BIN" "$APP/Contents/MacOS/DSHLauncher"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"

echo ""
echo "==> 完成 ✅ 应用位于: $APP"
echo "    打开方式: open \"$APP\""
