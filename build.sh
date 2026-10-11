#!/bin/zsh
# Build SenKey.app (chỉ cần Xcode Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SenKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Chạy test engine"
swiftc -O -swift-version 5 -o build/EngineTests Sources/VietEngine/*.swift Sources/EngineTests/main.swift
./build/EngineTests

echo "▸ Biên dịch app (universal)"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 \
    -o build/SenKey-$arch Sources/VietEngine/*.swift Sources/SenKey/*.swift
done
lipo -create -output "$APP/Contents/MacOS/SenKey" build/SenKey-arm64 build/SenKey-x86_64
rm build/SenKey-arm64 build/SenKey-x86_64

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>vn.senkey.app</string>
  <key>CFBundleName</key><string>SenKey</string>
  <key>CFBundleDisplayName</key><string>SenKey</string>
  <key>CFBundleExecutable</key><string>SenKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Hardened runtime (--options runtime): chặn nạp thư viện lạ vào tiến trình đang có quyền đọc phím.
# Ký bằng chứng chỉ "SenKey Dev" (tạo bằng ./make-cert.sh) để giữ quyền Trợ năng qua các lần build.
# Chưa có chứng chỉ thì ký ad-hoc (mỗi lần build phải cấp lại quyền).
# Ai có khoá này thì ký được app giả mà macOS coi là SenKey (có luôn quyền đọc phím), nên keychain
# chỉ mở bằng passphrase gõ tay và được khoá lại ngay sau khi ký.
SIGN_DIR="$HOME/Library/Application Support/SenKey/signing"
SIGN_KEYCHAIN="$SIGN_DIR/senkey-signing.keychain-db"
if [[ -f "$SIGN_KEYCHAIN" ]]; then
  if [[ -e "$SIGN_DIR/keychain-password" ]]; then
    echo "✗ Còn file mật khẩu keychain dạng chữ thường. Chạy ./make-cert.sh một lần để chuyển sang passphrase." >&2
    exit 1
  fi
  trap 'security lock-keychain "$SIGN_KEYCHAIN" 2>/dev/null || true' EXIT
  trap 'exit 130' INT TERM HUP   # zsh không chạy trap EXIT khi bị Ctrl-C; đổi thành exit để vẫn khoá keychain
  echo "▸ Ký bằng chứng chỉ SenKey Dev — nhập passphrase của keychain ký"
  echo "  (Chuyển SenKey sang En trước khi gõ: lời hỏi trong Terminal không phải ô mật khẩu thật nên SenKey sẽ thêm dấu.)"
  security unlock-keychain "$SIGN_KEYCHAIN"
  codesign --force --options runtime --keychain "$SIGN_KEYCHAIN" --sign "SenKey Dev" "$APP"
  security lock-keychain "$SIGN_KEYCHAIN"
  echo "✓ Xong: $APP (ký bằng chứng chỉ SenKey Dev)"
else
  codesign --force --options runtime --sign - "$APP"
  echo "✓ Xong: $APP (ký ad-hoc — chạy ./make-cert.sh để không phải cấp lại quyền mỗi lần build)"
fi
