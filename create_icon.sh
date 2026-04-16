#!/bin/bash

# VibeMove Icon Generator
# -----------------------

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 input_image output.icns"
    exit 1
fi

INPUT_IMAGE=$1
OUTPUT_ICNS=$2
ICONSET="VibeIcon.iconset"

mkdir -p "$ICONSET"

# 1. Convert input to a clean PNG first (since input might be JPEG)
echo "🔄 正在准备原始图片..."
sips -s format png "$INPUT_IMAGE" --out "temp_input.png"

# 2. Resize images into the iconset format
echo "📐 正在生成不同比例的图标..."
sips -z 16 16     "temp_input.png" --out "${ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     "temp_input.png" --out "${ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "temp_input.png" --out "${ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     "temp_input.png" --out "${ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "temp_input.png" --out "${ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   "temp_input.png" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "temp_input.png" --out "${ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   "temp_input.png" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "temp_input.png" --out "${ICONSET}/icon_512x512.png" > /dev/null
sips -z 1024 1024 "temp_input.png" --out "${ICONSET}/icon_512x512@2x.png" > /dev/null

# 3. Convert to icns
echo "🏗️ 正在构造 .icns 容器..."
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"

# 4. Cleanup
rm -rf "$ICONSET"
rm "temp_input.png"

echo "✅ 成功创建 $OUTPUT_ICNS"
