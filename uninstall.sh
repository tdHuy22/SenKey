#!/bin/zsh
# Gỡ SenKey hoàn toàn khỏi máy (không xoá thư mục mã nguồn)
set -uo pipefail
BUNDLE_ID="vn.senkey.app"

echo "▸ Thoát SenKey"
pkill -x SenKey 2>/dev/null || true
sleep 1

echo "▸ Xoá /Applications/SenKey.app"
rm -rf /Applications/SenKey.app

echo "▸ Xoá quyền Trợ năng đã cấp"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "▸ Xoá cài đặt đã lưu (kiểu gõ, danh sách ứng dụng)"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "(Chứng chỉ ký SenKey Dev vẫn giữ lại. Xoá nếu không build nữa:"
echo "   security delete-keychain \"$HOME/Library/Application Support/SenKey/signing/senkey-signing.keychain-db\""
echo "   rm -rf \"$HOME/Library/Application Support/SenKey\")"

cat <<MSG

✓ Đã gỡ SenKey.

Nếu trước đó bạn bật "Khởi động cùng macOS", hãy kiểm tra
Cài đặt hệ thống → Cài đặt chung → Mục đăng nhập, và xoá SenKey nếu vẫn còn.
Nhớ thêm lại bộ gõ tiếng Việt khác nếu cần (Bàn phím → Nguồn đầu vào).
MSG
