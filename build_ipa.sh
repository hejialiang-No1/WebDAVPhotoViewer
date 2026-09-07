#!/bin/zsh
# =============================================================================
#  WebDAVPhotoViewer — 企业版一键出包脚本 (In-House / Enterprise)
# =============================================================================
#  前置条件：
#    1. 本机已安装 Xcode（且装有 iOS 模拟器运行时，用于编译 App 图标）。
#    2. 你的「企业分发证书 (In-House)」+ 私钥已导入本机“登录”钥匙串。
#    3. 已从 Apple Developer 企业后台下载好对应的
#       In-House 描述文件 (.mobileprovision)，并双击安装到本机。
#
#  用法：
#    ./build_ipa.sh \
#        -t <TeamID> \
#        -i "<签名身份，例如: iPhone Distribution: Your Company Inc. (ABCDE12345)>" \
#        -p <描述文件UUID，例如: 3F8C2A1B-9D4E-4F7A-...> \
#        -b <BundleID，例如: com.yourcompany.WebDAVPhotoViewer>
#
#  TeamID / 描述文件UUID 查看方式：
#    security find-identity -v -p codesigning        # 看身份与 TeamID
#    ls ~/Library/MobileDevice/"Provisioning Profiles"/  # 看已装描述文件
#    (描述文件 UUID = 文件名去掉 .mobileprovision)
# =============================================================================
set -e

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

PROJ="WebDAVPhotoViewer.xcodeproj"
TARGET="WebDAVPhotoViewer"
OUT="build"
ARCHIVE="$OUT/WebDAVPhotoViewer.xcarchive"

TEAM=""; IDENTITY=""; PROFILE=""; BUNDLE_ID="com.yourcompany.WebDAVPhotoViewer"
while getopts "t:i:p:b:" opt; do
  case "$opt" in
    t) TEAM="$OPTARG" ;;
    i) IDENTITY="$OPTARG" ;;
    p) PROFILE="$OPTARG" ;;
    b) BUNDLE_ID="$OPTARG" ;;
    *) echo "未知参数: $opt"; exit 1 ;;
  esac
done

[ -z "$TEAM" ]     && { echo "❌ 缺少 -t <TeamID>"; exit 1; }
[ -z "$IDENTITY" ] && { echo "❌ 缺少 -i \"<签名身份名称>\""; exit 1; }
[ -z "$PROFILE" ]  && { echo "❌ 缺少 -p <描述文件UUID>"; exit 1; }

mkdir -p "$OUT"

# ---- 生成 ExportOptions.plist（企业分发，手动签名）----
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>enterprise</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROFILE</string>
    </dict>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> [1/2] Archive (Release, iphoneos) ..."
xcodebuild archive \
    -project "$PROJ" \
    -target "$TARGET" \
    -sdk iphoneos \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER="$PROFILE" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"

echo "==> [2/2] 导出 IPA ..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/IPA"

echo ""
echo "✅ 完成！签名 IPA 位于："
echo "   $OUT/IPA/WebDAVPhotoViewer.ipa"
