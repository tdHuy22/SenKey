#!/bin/zsh
# Tạo chứng chỉ ký mã tự ký "SenKey Dev" trong một keychain riêng (không đụng keychain đăng nhập).
# Ký bằng chứng chỉ cố định → macOS nhận ra các bản build là cùng một app → không phải cấp lại quyền Trợ năng.
#
# Ai có khoá này thì ký được app giả mà macOS coi là SenKey (có luôn quyền đọc phím), nên keychain chỉ
# mở bằng passphrase bạn tự đặt (cất trong trình quản lý mật khẩu), không lưu ra file, tự khoá sau 5 phút.
# Máy còn file keychain-password của bản cũ thì script chuyển keychain sang passphrase rồi xoá file đó.
set -euo pipefail
cd "$(dirname "$0")"

NAME="SenKey Dev"
DIR="$HOME/Library/Application Support/SenKey/signing"
KEYCHAIN="$DIR/senkey-signing.keychain-db"
PASSFILE="$DIR/keychain-password"   # chỉ còn ở máy tạo chứng chỉ bằng bản cũ của script này
# zsh không chạy trap EXIT khi bị Ctrl-C: đổi tín hiệu thành exit để phần dọn dẹp luôn chạy.
trap 'exit 130' INT TERM HUP

PASSPHRASE_TIP="(Chuyển SenKey sang En trước khi gõ: lời hỏi trong Terminal không phải ô mật khẩu thật nên SenKey sẽ thêm dấu.)"

if [[ -f "$KEYCHAIN" && -e "$PASSFILE" ]]; then
  echo "▸ Chuyển keychain ký sang passphrase do bạn đặt (bỏ file mật khẩu dạng chữ thường)"
  trap 'security lock-keychain "$KEYCHAIN" 2>/dev/null || true' EXIT
  OLD="$(cat "$PASSFILE")"
  security unlock-keychain -p "$OLD" "$KEYCHAIN"
  security set-keychain-settings -l -u -t 300 "$KEYCHAIN"   # khoá khi ngủ và sau 5 phút
  echo "Đặt passphrase mới (nên dài, cất vào trình quản lý mật khẩu; mất là phải khôi phục từ bản sao lưu)."
  echo "$PASSPHRASE_TIP"
  security set-keychain-password -o "$OLD" "$KEYCHAIN"
  unset OLD
  security lock-keychain "$KEYCHAIN"
  rm -f "$PASSFILE"
  echo "✓ Đã chuyển. Từ giờ build.sh, install.sh, package.sh sẽ hỏi passphrase này khi ký."
  exit 0
fi

if [[ -f "$KEYCHAIN" ]]; then
  echo "Đã có chứng chỉ tại: $KEYCHAIN"
  echo "(Muốn tạo lại: xoá thư mục \"$DIR\" rồi chạy lại script. Chứng chỉ mới làm mọi người dùng phải cấp lại quyền.)"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
rm -f "$PASSFILE"   # file mật khẩu sót lại từ keychain cũ đã xoá: vô nghĩa, và sẽ làm build.sh từ chối chạy
TMP="$(mktemp -d)"
DONE=0
# Dừng giữa chừng thì xoá keychain dở dang, để lần chạy sau tạo lại từ đầu thay vì dùng keychain thiếu bước.
cleanup() {
  rm -rf "$TMP"
  if (( DONE )); then
    security lock-keychain "$KEYCHAIN" 2>/dev/null || true
  elif [[ -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null || rm -f "$KEYCHAIN"
  fi
}
trap cleanup EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "▸ Tạo khoá và chứng chỉ (hạn 20 năm)"
# Mật khẩu .p12 tạm chỉ dùng để nhập vào keychain; khoá dạng thường bị xoá ngay khi đã đóng gói.
P12PASS="$(/usr/bin/openssl rand -hex 24)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:"$P12PASS" 2>/dev/null
rm -f "$TMP/key.pem"

echo "▸ Tạo keychain riêng. Đặt passphrase (nên dài, cất vào trình quản lý mật khẩu)."
echo "$PASSPHRASE_TIP"
security create-keychain "$KEYCHAIN"
security set-keychain-settings -l -u -t 300 "$KEYCHAIN"   # khoá khi ngủ và sau 5 phút
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
rm -f "$TMP/cert.p12"
echo "▸ Cho phép codesign dùng khoá — nhập lại passphrase:"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null
DONE=1

echo "✓ Đã tạo chứng chỉ \"$NAME\" trong $KEYCHAIN"
echo "  Nhớ sao lưu ra ngoài máy, ví dụ:"
echo "    security export -k \"$KEYCHAIN\" -t identities -f pkcs12 -o ~/SenKey-Dev.p12"
echo "  rồi chép ~/SenKey-Dev.p12 sang USB hay ổ mã hoá và xoá bản trên máy."
