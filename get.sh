#!/bin/bash
# Cài hoặc cập nhật SenKey bằng một lệnh (không cần Xcode, không bị Gatekeeper chặn):
#   curl -fsSL https://raw.githubusercontent.com/tdHuy22/SenKey/main/get.sh | bash
set -euo pipefail

URL="https://github.com/tdHuy22/SenKey/releases/latest/download/SenKey.zip"
BUNDLE_ID="vn.senkey.app"
# Chữ ký mọi bản phát hành phải khớp: đúng chứng chỉ "SenKey Dev" của tác giả (ghim theo hash, không theo tên).
# macOS cấp quyền Trợ năng theo đúng yêu cầu này. package.sh đọc dòng dưới để kiểm bản sắp phát hành.
REQUIREMENT='=identifier "vn.senkey.app" and certificate leaf = H"e90227565deafdcd07f260406f4934fe32ed72d6"'

designated() { codesign -dr - "$1" 2>/dev/null | grep '^designated' || true; }

# App phải là thư mục thật, chữ ký nguyên vẹn và khớp yêu cầu ghim ở trên. Yêu cầu gắn trong app cũng phải
# đúng bằng nó: macOS cấp quyền theo yêu cầu gắn trong app, nếu nó lỏng hơn thì app giả cũng hưởng quyền.
verify_app() {
  [[ -d "$1" && ! -L "$1" ]] \
    && codesign --verify --strict --deep -R "$REQUIREMENT" "$1" 2>/dev/null \
    && [[ "$(designated "$1")" == "designated => ${REQUIREMENT#=}" ]]
}

# Toàn bộ script nằm trong main, gọi ở dòng cuối: tải đứt giữa chừng thì không chạy nửa script.
main() {
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if (( major < 13 )); then
    echo "✗ SenKey cần macOS 13 (Ventura) trở lên. Máy bạn đang chạy macOS $(sw_vers -productVersion)."
    exit 1
  fi

  local DEST="/Applications"
  if [[ ! -w "$DEST" ]]; then
    DEST="$HOME/Applications"   # tài khoản không phải admin
    mkdir -p "$DEST"
  fi

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  echo "▸ Đang tải SenKey…"
  curl -fL --progress-bar -o "$TMP/SenKey.zip" "$URL"
  mkdir "$TMP/x"
  ditto -x -k "$TMP/SenKey.zip" "$TMP/x"

  echo "▸ Kiểm tra chữ ký"
  if ! verify_app "$TMP/x/SenKey.app"; then
    echo "✗ Bản tải về không mang chữ ký của SenKey nên không được cài. Bản đang có trên máy giữ nguyên." >&2
    echo "  Hãy báo lỗi tại https://github.com/tdHuy22/SenKey/issues" >&2
    exit 1
  fi

  local OLD_DR
  OLD_DR="$(designated "$DEST/SenKey.app")"

  if pgrep -x SenKey >/dev/null; then
    echo "▸ Thoát bản đang chạy"
    pkill -x SenKey || true
    sleep 1
  fi

  if [[ -d "$DEST/SenKey.app" && "$(designated "$TMP/x/SenKey.app")" != "$OLD_DR" ]]; then
    # Bản cũ ký khác (vd bản tự build) → quyền cũ không còn khớp; xoá khi app đã thoát để tránh treo.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  echo "▸ Cài vào $DEST"
  rm -rf "$DEST/SenKey.app"
  ditto "$TMP/x/SenKey.app" "$DEST/SenKey.app"
  xattr -dr com.apple.quarantine "$DEST/SenKey.app" 2>/dev/null || true

  open "$DEST/SenKey.app"

  cat <<MSG

✓ Đã cài SenKey $(defaults read "$DEST/SenKey.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)

Cửa sổ hướng dẫn của SenKey sẽ hiện ra — làm theo từng bước là xong.
Muốn cập nhật sau này: chạy lại đúng lệnh vừa rồi.
MSG
}

main "$@"
