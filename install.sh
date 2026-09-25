#!/bin/zsh
# Build và cài SenKey vào /Applications
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

designated() { codesign -dr - "$1" 2>/dev/null | grep '^designated' || true; }
NEW_DR="$(designated build/SenKey.app)"
OLD_DR="$(designated /Applications/SenKey.app)"

echo "▸ Thoát bản đang chạy"
pkill -x SenKey 2>/dev/null || true
sleep 1

NEED_GRANT=0
if [[ "$NEW_DR" != *"certificate leaf"* || "$NEW_DR" != "$OLD_DR" ]]; then
  # Chữ ký đổi (hoặc ad-hoc) → quyền cũ không còn khớp; xoá khi app đã thoát để tránh treo.
  echo "▸ Chữ ký thay đổi → xoá quyền Trợ năng cũ"
  tccutil reset Accessibility vn.senkey.app >/dev/null 2>&1 || true
  NEED_GRANT=1
fi

if [[ -d /Applications/GoViet.app ]]; then
  # Tên cũ trước khi đổi thành SenKey: thoát trước rồi mới xoá quyền để tránh treo.
  echo "▸ Gỡ bản cũ GoViet.app"
  pkill -x GoViet 2>/dev/null || true
  sleep 1
  tccutil reset Accessibility vn.goviet.app >/dev/null 2>&1 || true
  rm -rf /Applications/GoViet.app
  NEED_GRANT=1
fi

echo "▸ Chép vào /Applications"
rm -rf /Applications/SenKey.app
ditto build/SenKey.app /Applications/SenKey.app

echo "▸ Mở SenKey"
open /Applications/SenKey.app

if [[ $NEED_GRANT == 1 ]]; then
cat <<MSG

✓ Đã cài SenKey vào /Applications.

Việc cần làm tiếp:
  1. Cấp quyền: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng → bật SenKey.
     Lưu ý: KHÔNG TẮT quyền của SenKey khi app đang chạy — hãy thoát SenKey trước.
  2. Cài đặt hệ thống → Bàn phím → Nguồn đầu vào → chỉ để lại "ABC".
  3. Biểu tượng "Vi"/"En" hiện trên menu bar là xong. Nhấn rồi thả ⌃⇧ để đảo Việt/Anh.
MSG
else
cat <<MSG

✓ Đã cập nhật SenKey. Chữ ký không đổi nên giữ nguyên quyền Trợ năng — không cần làm gì thêm.
MSG
fi
