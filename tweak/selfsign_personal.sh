#!/usr/bin/env bash
# 用已安装的 Apple Development 证书（个人免费团队）整包重签。
#
# 关键点：
#   1. 个人免费证书的描述文件只覆盖「Xcode 为该 App 生成的 App ID」，
#      所以必须先把 bundle id 改成唯一值（默认 com.dragon.read.noad），
#      并让 Xcode 为这个 id 生成描述文件（第一次用 Xcode 建个同名空工程跑一遍即可）。
#   2. 免费证书 7 天过期，到期重跑本脚本即可。
#   3. 免费账号不支持 App Groups / iCloud / Push，entitlements 里已剔除。
#
# 用法:
#   ./selfsign_personal.sh <profile.mobileprovision> [bundle_id]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUILD="$ROOT/work/build"
APP="$BUILD/Payload/Reading.app"

PROFILE="${1:?需要先用 Xcode 生成 profile 并给出路径}"
BUNDLE_ID="${2:-com.dragon.read.noad}"
TEAM_ID="$(security cms -D -i "$PROFILE" > /tmp/_selfsign_profile.plist && python3 -I -c "
import plistlib
p=plistlib.load(open('/tmp/_selfsign_profile.plist','rb'))
print(p['Entitlements']['com.apple.developer.team-identifier'])")"

IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
[ -n "$IDENTITY" ] || { echo "钥匙串里没有 Apple Development 证书"; exit 1; }
echo "Team   : $TEAM_ID"
echo "Identity: $IDENTITY"
echo "Bundle : $BUNDLE_ID"

ENT_DIR="$BUILD/ent"
mkdir -p "$ENT_DIR"

cat > "$ENT_DIR/app.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM_ID.$BUNDLE_ID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
<key>get-task-allow</key><true/>
</dict></plist>
EOF

echo "== 清理旧签名 =="
rm -rf "$APP/_CodeSignature"
find "$APP/Frameworks" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
cp "$PROFILE" "$APP/embedded.mobileprovision"

sign() { codesign -f -s "$IDENTITY" --timestamp=none --generate-entitlement-der --entitlements "$2" "$1"; }

echo "== Frameworks =="
for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  exe="$fw/$(basename "$fw" .framework)"
  [ -f "$exe" ] && sign "$exe" "$ENT_DIR/app.plist" || true
  sign "$fw" "$ENT_DIR/app.plist"
done
for d in "$APP"/Frameworks/*.dylib; do [ -f "$d" ] && sign "$d" "$ENT_DIR/app.plist"; done

echo "== 主应用 =="
sign "$APP/Reading" "$ENT_DIR/app.plist"
sign "$APP"         "$ENT_DIR/app.plist"

echo "== 校验 =="
codesign -v --deep --strict "$APP" && echo OK

echo "== 打包 =="
OUT="$ROOT/番茄去广告.ipa"
rm -f "$OUT"
(cd "$BUILD" && zip -qry "$OUT" Payload)
ls -lh "$OUT"
