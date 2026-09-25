#!/bin/zsh
# Gỡ GoViet hoàn toàn khỏi máy (không xoá thư mục mã nguồn)
set -uo pipefail
BUNDLE_ID="vn.goviet.app"

echo "▸ Thoát GoViet"
pkill -x GoViet 2>/dev/null || true
sleep 1

echo "▸ Xoá /Applications/GoViet.app"
rm -rf /Applications/GoViet.app

echo "▸ Xoá quyền Trợ năng đã cấp"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "▸ Xoá cài đặt đã lưu (kiểu gõ, danh sách ứng dụng)"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "(Chứng chỉ ký GoViet Dev vẫn giữ lại. Xoá nếu không build nữa:"
echo "   security delete-keychain \"$HOME/Library/Application Support/GoViet/signing/goviet-signing.keychain-db\""
echo "   rm -rf \"$HOME/Library/Application Support/GoViet\")"

cat <<MSG

✓ Đã gỡ GoViet.

Nếu trước đó bạn bật "Khởi động cùng macOS", hãy kiểm tra
Cài đặt hệ thống → Cài đặt chung → Mục đăng nhập, và xoá GoViet nếu vẫn còn.
Nhớ thêm lại bộ gõ tiếng Việt khác nếu cần (Bàn phím → Nguồn đầu vào).
MSG
