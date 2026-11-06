#!/usr/bin/env bash
# renew.sh —— 免费证书 7 天到期后的重新签名（不改任何代码，只重签 + 重装）
#
# 前提：work/build 里的包已经是「注入完成、bundle id = com.dragon.read-noad」的状态。
# 描述文件由 Xcode 在 ~/Library/Developer/Xcode/UserData/Provisioning Profiles/ 里自动更新。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="${APP:-$ROOT/work/build/Payload/Reading.app}"
ENT="${ENT:-$ROOT/work/build/ent/app.plist}"
BUNDLE_ID="${BUNDLE_ID:-com.dragon.read-noad}"
TEAM_ID="${TEAM_ID:?请设置 TEAM_ID，例如 export TEAM_ID=ABCDE12345}"
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')}"
[ -n "$IDENTITY" ] || { echo "钥匙串里没有 Apple Development 证书"; exit 1; }

# 找最新一份匹配 bundle id 的描述文件
PROFILE=""
for f in "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
         "$HOME"/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
  [ -f "$f" ] || continue
  security cms -D -i "$f" > /tmp/_renew.plist 2>/dev/null || continue
  id="$(python3 -I -c "import plistlib;print(plistlib.load(open('/tmp/_renew.plist','rb'))['Entitlements'].get('application-identifier',''))")"
  if [ "$id" = "$TEAM_ID.$BUNDLE_ID" ]; then PROFILE="$f"; fi
done
[ -n "$PROFILE" ] || { echo "找不到 $BUNDLE_ID 的描述文件，先在 Xcode 里 Run 一次"; exit 1; }
echo "profile: $PROFILE"

cp "$PROFILE" "$APP/embedded.mobileprovision"

echo "== 重签 =="
sign() { codesign -f -s "$IDENTITY" --timestamp=none --entitlements "$ENT" "$1"; }
for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  exe="$fw/$(basename "$fw" .framework)"
  [ -f "$exe" ] && sign "$exe"
  sign "$fw"
done
for d in "$APP"/Frameworks/*.dylib; do [ -f "$d" ] && sign "$d"; done
sign "$APP/Reading"
sign "$APP"

codesign -v --deep --strict "$APP" && echo "签名校验通过"

echo "== 重装 =="
DEVICE="${DEVICE:?请设置 DEVICE，例如 export DEVICE=00008101-XXXXXXXXXXXXXXXX}"
ios-deploy --bundle "$APP" --id "$DEVICE" --justlaunch 2>&1 | grep -E 'InstallComplete|Installed package|error' | head -5
