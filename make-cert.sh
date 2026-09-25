#!/bin/zsh
# Tạo chứng chỉ ký mã tự ký "SenKey Dev" trong một keychain riêng (không đụng keychain đăng nhập).
# Ký bằng chứng chỉ cố định → macOS nhận ra các bản build là cùng một app → không phải cấp lại quyền Trợ năng.
set -euo pipefail
cd "$(dirname "$0")"

NAME="SenKey Dev"
DIR="$HOME/Library/Application Support/SenKey/signing"
KEYCHAIN="$DIR/senkey-signing.keychain-db"
PASSFILE="$DIR/keychain-password"

if [[ -f "$KEYCHAIN" ]]; then
  echo "Đã có chứng chỉ tại: $KEYCHAIN"
  echo "(Muốn tạo lại: xoá thư mục \"$DIR\" rồi chạy lại script.)"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Mật khẩu ngẫu nhiên, chỉ dùng cho keychain riêng này
/usr/bin/openssl rand -hex 24 > "$PASSFILE"
chmod 600 "$PASSFILE"
PASS="$(cat "$PASSFILE")"

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
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:"$PASS" 2>/dev/null

echo "▸ Tạo keychain riêng và nhập chứng chỉ"
security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # không tự khoá
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null

echo "✓ Đã tạo chứng chỉ \"$NAME\" trong $KEYCHAIN"
