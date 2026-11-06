#!/usr/bin/env bash
# 自签全流程：编译 tweak -> 注入 -> 改 bundle id -> 重签 -> 打包
#
# 用法:
#   ./build_signed.sh <profile.mobileprovision> <team_id> <签名身份名> [主 bundle id]
#
# 不带参数时只做「编译 + 注入」，输出可进一步重签的 Payload 目录。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ORIG_IPA="${ORIG_IPA:-$HOME/Downloads/com.dragon.read_7.4.1_maclub.net.ipa}"
WORK="$ROOT/work"
BUILD="$WORK/build"
APP="$BUILD/Payload/Reading.app"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

PROFILE="${1:-}"
TEAM_ID="${2:-}"
IDENTITY="${3:-}"
MAIN_ID="${4:-com.dragon.read.noad}"

echo "== 1/6 解包 =="
if [ ! -d "$APP" ]; then
  rm -rf "$BUILD" && mkdir -p "$BUILD"
  unzip -q "$ORIG_IPA" -d "$BUILD"
fi
echo "Payload: $BUILD ($(du -sh "$BUILD" | cut -f1))"

echo "== 2/6 编译 NoAd.dylib =="
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=14.0 \
  -dynamiclib -fobjc-arc -O2 -isysroot "$SDK" \
  -o "$HERE/NoAd.dylib" "$HERE/NoAd.m" -framework Foundation
file "$HERE/NoAd.dylib"

echo "== 3/6 注入 =="
cp "$HERE/NoAd.dylib" "$APP/Frameworks/NoAd.dylib"
if ! otool -l "$APP/Reading" | grep -q "NoAd.dylib"; then
  python3 -I "$HERE/patch_loadcmd.py" "$APP/Reading" "@executable_path/Frameworks/NoAd.dylib"
else
  echo "已注入，跳过"
fi

echo "== 4/6 改 bundle id =="
python3 -I "$HERE/patch_bundles.py" "$BUILD" "$MAIN_ID"

if [ -z "$PROFILE" ]; then
  echo
  echo "未提供描述文件，停在「待重签」状态。重签请执行："
  echo "  ./resign.sh \"$BUILD\" <profile.mobileprovision> <team_id> \"<identity>\" $MAIN_ID"
  exit 0
fi

echo "== 5/6 重签 =="
"$HERE/resign.sh" "$BUILD" "$PROFILE" "$TEAM_ID" "$IDENTITY" "$MAIN_ID"

echo "== 6/6 打包 =="
OUT="$ROOT/番茄去广告.ipa"
rm -f "$OUT"
(cd "$BUILD" && zip -qry "$OUT" Payload)
ls -lh "$OUT"
echo
echo "安装："
echo "  ios-deploy --bundle \"$BUILD/Payload/Reading.app\""
echo "  或  ideviceinstaller -i \"$OUT\""
