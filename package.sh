#!/bin/bash

# VibeMove App Packaging Script
# -----------------------------

APP_NAME="FlowGym"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "📦 正在编译 FlowGym (Release 模式)..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ 编译失败。"
    exit 1
fi

echo "📂 正在构建 App 目录结构..."
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

echo "🚚 正在拷贝二进制文件与图标..."
cp ".build/release/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "VibeIcon.icns" "${RESOURCES}/VibeIcon.icns"

echo "📝 正在生成 Info.plist..."
# 使用项目自带的 Info.plist
cp "Sources/FlowGym/Info.plist" "${CONTENTS}/Info.plist"

# 确保 Info.plist 中有必要的 Bundle 信息
# (Info.plist 本身已经包含了 Camera 权限说明)

echo "✅ 打包完成: ${APP_BUNDLE}"
echo "------------------------------------------------"
echo "🚀 您现在可以双击运行 ${APP_BUNDLE} 了！"
echo "💡 注意：第一次运行涉及模拟按键，请确保在"
echo "   系统设置 -> 隐私与安全性 -> 辅助功能 中勾选该应用。"
echo "------------------------------------------------"
