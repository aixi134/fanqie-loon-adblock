#!/usr/bin/env bash
# resign.sh —— 自签整包脚本
#
# 用法:
#   ./resign.sh <payload 目录> <profile.mobileprovision> <team_id> <签名身份名> [主 bundle id]
#
# 例（企业/通配符描述文件）:
#   ./resign.sh ../work/ipa_patched_Payload cert.mobileprovision <TEAM_ID> \
#                "iPhone Distribution: XXX" com.dragon.read.noad
#
# 例（个人免费证书、7 天）:
#   ./resign.sh ../work/ipa_patched_Payload ~/Library/MobileDevice/Provisioning\ Profiles/xxx.mobileprovision \
#                <TEAM_ID> "Apple Development: xxx (xxx)" com.dragon.read.noad
#
# 前提:
#   - 描述文件 App ID 必须是通配符 (<team>.*)，否则签不了 com.dragon.read，脚本会先检查后退出。
#   - p12 已导入钥匙串，<签名身份名> 与 `security find-identity -v -p codesigning` 显示的一致。
set -euo pipefail

PAYLOAD_DIR="${1:?payload dir}"
PROFILE="${2:?mobileprovision}"
TEAM_ID="${3:?team id}"
IDENTITY="${4:?codesign identity}"
MAIN_ID="${5:-com.dragon.read}"

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$PAYLOAD_DIR/Payload/Reading.app"
ENT_DIR="$PAYLOAD_DIR/entitlements"
mkdir -p "$ENT_DIR"

bundle_id_of() {
  python3 -I -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb')).get('CFBundleIdentifier'))" "$1/Info.plist"
}

# ---------- 0. 读取描述文件 ----------
echo "== 读取描述文件 =="
security cms -D -i "$PROFILE" > "$PAYLOAD_DIR/profile.plist"
python3 -I - "$PAYLOAD_DIR/profile.plist" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
print("  Name              :", p.get("Name"))
print("  TeamName          :", p.get("TeamName"))
print("  ExpirationDate    :", p.get("ExpirationDate"))
print("  ProvisionsAllDevices:", p.get("ProvisionsAllDevices", False))
print("  AppID             :", p.get("Entitlements", {}).get("application-identifier"))
print("  DeviceCount       :", len(p.get("ProvisionedDevices", []) or []))
PY

# ---------- 1. 改 bundle id（仅当指定了非默认主 id）----------
if [ "$MAIN_ID" != "com.dragon.read" ]; then
  echo "== 改写 bundle id =="
  python3 -I "$HERE/patch_bundles.py" "$PAYLOAD_DIR" "$MAIN_ID"
fi

MAIN_BID="$(bundle_id_of "$APP")"
PUSH_BID="$(bundle_id_of "$APP/PlugIns/ReadingNotificationExtension.appex")"
WIDGET_BID="$(bundle_id_of "$APP/PlugIns/ReadingWidgetExtension.appex")"
echo "主应用     : $MAIN_BID"
echo "推送扩展   : $PUSH_BID"
echo "小组件扩展 : $WIDGET_BID"

# ---------- 2. 生成 entitlements ----------
gen() {  # gen <bundle id> <out key> [kind]
  python3 -I "$HERE/gen_entitlements.py" "$PAYLOAD_DIR/profile.plist" "$1" "$TEAM_ID" \
          "$ENT_DIR/$2.plist" "${3:-ent}"
}
gen "$MAIN_BID"   app    ent
gen "$PUSH_BID"   push   ent
gen "$WIDGET_BID" widget ent

python3 -I - "$ENT_DIR/app.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
e = plistlib.load(open(path, "rb"))
e["com.apple.developer.associated-domains"] = [
    "applinks:reading.snssdk.com",
    "applinks:zlink.fqnovel.com",
    "applinks:fqnovel.ugurl.cn",
]
plistlib.dump(e, open(path, "wb"))
PY

# ---------- 3. 清理原签名 ----------
echo "== 清理原签名 =="
rm -rf "$APP/_CodeSignature"
rm -f  "$APP/Reading.orig"
find "$APP/Frameworks" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP/PlugIns"    -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true

# ---------- 4. 替换描述文件 ----------
cp "$PROFILE" "$APP/embedded.mobileprovision"
find "$APP/PlugIns" -name "embedded.mobileprovision" -exec cp "$PROFILE" {} \;

# ---------- 5. 重签 ----------
sign() {
  codesign -f -s "$IDENTITY" --timestamp=none --generate-entitlement-der \
           --entitlements "$2" "$1"
}

echo "== 签 Frameworks =="
for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  exe="$fw/$(basename "$fw" .framework)"
  [ -f "$exe" ] && sign "$exe" "$ENT_DIR/app.plist"
  sign "$fw" "$ENT_DIR/app.plist"
done

echo "== 签独立 dylib =="
for d in "$APP"/Frameworks/*.dylib; do
  [ -f "$d" ] && sign "$d" "$ENT_DIR/app.plist"
done

echo "== 签扩展 =="
push_exe="$(python3 -I -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb'))['CFBundleExecutable'])" "$APP/PlugIns/ReadingNotificationExtension.appex/Info.plist")"
widget_exe="$(python3 -I -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb'))['CFBundleExecutable'])" "$APP/PlugIns/ReadingWidgetExtension.appex/Info.plist")"
sign "$APP/PlugIns/ReadingNotificationExtension.appex/$push_exe"   "$ENT_DIR/push.plist"
sign "$APP/PlugIns/ReadingNotificationExtension.appex"             "$ENT_DIR/push.plist"
sign "$APP/PlugIns/ReadingWidgetExtension.appex/$widget_exe"       "$ENT_DIR/widget.plist"
sign "$APP/PlugIns/ReadingWidgetExtension.appex"                   "$ENT_DIR/widget.plist"

echo "== 签主应用 =="
sign "$APP/Reading" "$ENT_DIR/app.plist"
sign "$APP"         "$ENT_DIR/app.plist"

# ---------- 6. 校验 ----------
echo "== 校验 =="
codesign -v --deep --strict "$APP" && echo "codesign 校验通过"
codesign -d --entitlements - "$APP" 2>/dev/null | head -14

echo
echo "完成。打包："
echo "  cd \"$PAYLOAD_DIR/..\" && zip -qry \"番茄去广告.ipa\" Payload"
