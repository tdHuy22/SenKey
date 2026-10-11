#!/bin/zsh
# Đóng gói bản phát hành: build/release/SenKey.zip (cho get.sh) và SenKey.dmg (kéo thả vào Applications).
# Phải build trên máy có chứng chỉ "SenKey Dev" để người dùng cập nhật không phải cấp lại quyền.
set -euo pipefail
cd "$(dirname "$0")"

# Kiểm đúng yêu cầu chữ ký mà get.sh của người dùng sẽ kiểm (một nguồn duy nhất: dòng REQUIREMENT trong get.sh).
# Kiểm theo hash chứng chỉ, không theo tên: ai cũng tạo được chứng chỉ tên "SenKey Dev".
REQUIREMENT="$(sed -n "s/^REQUIREMENT='\(.*\)'$/\1/p" get.sh)"
if [[ -z "$REQUIREMENT" ]]; then
  echo "✗ Không đọc được REQUIREMENT trong get.sh." >&2
  exit 1
fi

./build.sh
if ! codesign --verify --strict --deep -R "$REQUIREMENT" build/SenKey.app \
   || [[ "$(codesign -dr - build/SenKey.app 2>/dev/null | grep '^designated')" != "designated => ${REQUIREMENT#=}" ]]; then
  echo "✗ App không khớp chữ ký ghim trong get.sh (chứng chỉ khác hoặc ký ad-hoc) — không phát hành." >&2
  echo "  Dùng đúng máy phát hành, hoặc khôi phục chứng chỉ SenKey Dev từ bản sao lưu." >&2
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
cat <<MSG

Phát hành (repo bật immutable releases: đăng rồi thì không sửa hay thay file được nữa):
  gh release create v$VERSION --draft --title "SenKey $VERSION" $OUT/SenKey.zip $OUT/SenKey.dmg
  (kiểm bản nháp trên GitHub)  gh release edit v$VERSION --draft=false
MSG
