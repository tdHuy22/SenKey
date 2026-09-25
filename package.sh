#!/bin/zsh
# Đóng gói bản phát hành: build/release/SenKey.zip (cho get.sh) và SenKey.dmg (kéo thả vào Applications).
# Phải build trên máy có chứng chỉ "SenKey Dev" để người dùng cập nhật không phải cấp lại quyền.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
SIGN_INFO="$(codesign -dvv build/SenKey.app 2>&1)"
if [[ "$SIGN_INFO" != *"Authority=SenKey Dev"* ]]; then
  echo "✗ App chưa được ký bằng chứng chỉ SenKey Dev — chạy ./make-cert.sh hoặc dùng đúng máy phát hành." >&2
  exit 1
fi

OUT=build/release
STAGE=build/dmg
rm -rf "$OUT" "$STAGE"
mkdir -p "$OUT" "$STAGE"

ditto -c -k --sequesterRsrc --keepParent build/SenKey.app "$OUT/SenKey.zip"

ditto build/SenKey.app "$STAGE/SenKey.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "SenKey" -srcfolder "$STAGE" -ov -format UDZO "$OUT/SenKey.dmg"
rm -rf "$STAGE"

VERSION="$(defaults read "$PWD/build/SenKey.app/Contents/Info" CFBundleShortVersionString)"
echo "✓ SenKey $VERSION"
(cd "$OUT" && shasum -a 256 SenKey.zip SenKey.dmg && du -h SenKey.zip SenKey.dmg)
