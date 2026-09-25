#!/bin/bash
# Cài hoặc cập nhật SenKey bằng một lệnh (không cần Xcode, không bị Gatekeeper chặn):
#   curl -fsSL https://raw.githubusercontent.com/tdHuy22/SenKey/main/get.sh | bash
set -euo pipefail

URL="https://github.com/tdHuy22/SenKey/releases/latest/download/SenKey.zip"
BUNDLE_ID="vn.senkey.app"

major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 13 )); then
  echo "✗ SenKey cần macOS 13 (Ventura) trở lên. Máy bạn đang chạy macOS $(sw_vers -productVersion)."
  exit 1
fi

DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"   # tài khoản không phải admin
  mkdir -p "$DEST"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Đang tải SenKey…"
curl -fL --progress-bar -o "$TMP/SenKey.zip" "$URL"
ditto -x -k "$TMP/SenKey.zip" "$TMP"

designated() { codesign -dr - "$1" 2>/dev/null | grep '^designated' || true; }
NEW_DR="$(designated "$TMP/SenKey.app")"
OLD_DR="$(designated "$DEST/SenKey.app")"

if pgrep -x SenKey >/dev/null; then
  echo "▸ Thoát bản đang chạy"
  pkill -x SenKey || true
  sleep 1
fi

if [[ -d "$DEST/SenKey.app" && "$NEW_DR" != "$OLD_DR" ]]; then
  # Chữ ký khác bản cũ (vd bản tự build) → quyền cũ không còn khớp; xoá khi app đã thoát để tránh treo.
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "▸ Cài vào $DEST"
rm -rf "$DEST/SenKey.app"
ditto "$TMP/SenKey.app" "$DEST/SenKey.app"
xattr -dr com.apple.quarantine "$DEST/SenKey.app" 2>/dev/null || true

open "$DEST/SenKey.app"

cat <<MSG

✓ Đã cài SenKey $(defaults read "$DEST/SenKey.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)

Cửa sổ hướng dẫn của SenKey sẽ hiện ra — làm theo từng bước là xong.
Muốn cập nhật sau này: chạy lại đúng lệnh vừa rồi.
MSG
