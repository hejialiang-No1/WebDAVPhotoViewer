#!/bin/zsh
# =============================================================================
#  WebDAVPhotoViewer — 重签脚本（把未签名/他人签名的 IPA 用你的企业证书重签）
# =============================================================================
#  用法：
#    ./resign.sh -i "<签名身份>" -p path/to/InHouse.mobileprovision \
#                [-b com.yourcompany.WebDAVPhotoViewer] <未签名.ipa>
#
#  说明：脚本会从描述文件里提取 entitlements，对整个 .app 重新 codesign，
#        然后重新打成 IPA。产物为 <原名>-resigned.ipa。
# =============================================================================
set -e

IDENTITY=""; PROFILE=""; BUNDLE_ID=""
while getopts "i:p:b:" opt; do
  case "$opt" in
    i) IDENTITY="$OPTARG" ;;
    p) PROFILE="$OPTARG" ;;
    b) BUNDLE_ID="$OPTARG" ;;
    *) echo "未知参数: $opt"; exit 1 ;;
  esac
done
shift $((OPTIND-1))

[ -z "$IDENTITY" ] && { echo "❌ 缺少 -i \"<签名身份名称>\""; exit 1; }
[ -z "$PROFILE" ]  && { echo "❌ 缺少 -p <描述文件路径.mobileprovision>"; exit 1; }
[ $# -lt 1 ]       && { echo "❌ 请传入待重签的 .ipa 路径"; exit 1; }

IPA="$1"
[ -f "$IPA" ] || { echo "❌ 找不到 IPA: $IPA"; exit 1; }
[ -f "$PROFILE" ] || { echo "❌ 找不到描述文件: $PROFILE"; exit 1; }

WORK=$(mktemp -d)
APP_NAME="WebDAVPhotoViewer.app"
IPA_NAME=$(basename "$IPA" .ipa)

echo "==> 解压 IPA ..."
unzip -q "$IPA" -d "$WORK"

APP="$WORK/Payload/$APP_NAME"
[ -d "$APP" ] || { echo "❌ Payload/$APP_NAME 不存在"; exit 1; }

# 若未指定 bundle id，则从原 app 读取
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist" 2>/dev/null || echo "")
fi

echo "==> 写入 embedded.mobileprovision ..."
cp "$PROFILE" "$APP/embedded.mobileprovision"

# 若指定了 bundle id，则同步进 app 的 Info.plist（必须与企业描述文件的 AppID 一致）
if [ -n "$BUNDLE_ID" ]; then
  echo "==> 同步 Bundle ID -> $BUNDLE_ID"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
fi

echo "==> 从描述文件提取 entitlements ..."
security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null || true
ENTITLEMENTS="$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Print :Entitlements" "$WORK/profile.plist" >/dev/null 2>&1 \
  && /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$WORK/profile.plist" "$ENTITLEMENTS" \
  || printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/>\n</plist>\n' > "$ENTITLEMENTS"

echo "==> 重新签名 ..."
# 1) 先签内部 frameworks（本工程无，但保留以防扩展）
for f in "$APP/Frameworks"/*; do
  [ -e "$f" ] || continue
  codesign --force --timestamp=none --sign "$IDENTITY" "$f"
done
# 2) 签主 app
codesign --force --timestamp=none --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" "$APP"

echo "==> 重新打包 IPA ..."
OUT_IPA="${IPA_NAME}-resigned.ipa"
( cd "$WORK" && zip -qr "$OLDPWD/$OUT_IPA" Payload )
echo ""
echo "✅ 重签完成：$OUT_IPA"
rm -rf "$WORK"
