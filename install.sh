#!/bin/zsh
# Build và cài GoViet vào /Applications
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

designated() { codesign -dr - "$1" 2>/dev/null | grep '^designated' || true; }
NEW_DR="$(designated build/GoViet.app)"
OLD_DR="$(designated /Applications/GoViet.app)"

echo "▸ Thoát bản đang chạy"
pkill -x GoViet 2>/dev/null || true
sleep 1

NEED_GRANT=0
if [[ "$NEW_DR" != *"certificate leaf"* || "$NEW_DR" != "$OLD_DR" ]]; then
  # Chữ ký đổi (hoặc ad-hoc) → quyền cũ không còn khớp; xoá khi app đã thoát để tránh treo.
  echo "▸ Chữ ký thay đổi → xoá quyền Trợ năng cũ"
  tccutil reset Accessibility vn.goviet.app >/dev/null 2>&1 || true
  NEED_GRANT=1
fi

echo "▸ Chép vào /Applications"
rm -rf /Applications/GoViet.app
ditto build/GoViet.app /Applications/GoViet.app

echo "▸ Mở GoViet"
open /Applications/GoViet.app

if [[ $NEED_GRANT == 1 ]]; then
cat <<MSG

✓ Đã cài GoViet vào /Applications.

Việc cần làm tiếp:
  1. Cấp quyền: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng → bật GoViet.
     Lưu ý: KHÔNG TẮT quyền của GoViet khi app đang chạy — hãy thoát GoViet trước.
  2. Cài đặt hệ thống → Bàn phím → Nguồn đầu vào → chỉ để lại "ABC".
  3. Biểu tượng "Vi"/"En" hiện trên menu bar là xong. Nhấn rồi thả ⌃⇧ để đảo Việt/Anh.
MSG
else
cat <<MSG

✓ Đã cập nhật GoViet. Chữ ký không đổi nên giữ nguyên quyền Trợ năng — không cần làm gì thêm.
MSG
fi
