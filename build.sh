#!/bin/zsh
# Build GoViet.app (chỉ cần Xcode Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/GoViet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Chạy test engine"
swiftc -O -swift-version 5 -o build/EngineTests Sources/VietEngine/*.swift Sources/EngineTests/main.swift
./build/EngineTests

echo "▸ Biên dịch app (universal)"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 \
    -o build/GoViet-$arch Sources/VietEngine/*.swift Sources/GoViet/*.swift
done
lipo -create -output "$APP/Contents/MacOS/GoViet" build/GoViet-arm64 build/GoViet-x86_64
rm build/GoViet-arm64 build/GoViet-x86_64

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>vn.goviet.app</string>
  <key>CFBundleName</key><string>GoViet</string>
  <key>CFBundleDisplayName</key><string>GoViet</string>
  <key>CFBundleExecutable</key><string>GoViet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Hardened runtime (--options runtime): chặn nạp thư viện lạ vào tiến trình đang có quyền đọc phím.
# Ký bằng chứng chỉ "GoViet Dev" (tạo bằng ./make-cert.sh) để giữ quyền Trợ năng qua các lần build.
# Chưa có chứng chỉ thì ký ad-hoc (mỗi lần build phải cấp lại quyền).
SIGN_DIR="$HOME/Library/Application Support/GoViet/signing"
SIGN_KEYCHAIN="$SIGN_DIR/goviet-signing.keychain-db"
if [[ -f "$SIGN_KEYCHAIN" && -f "$SIGN_DIR/keychain-password" ]]; then
  security unlock-keychain -p "$(cat "$SIGN_DIR/keychain-password")" "$SIGN_KEYCHAIN"
  codesign --force --options runtime --keychain "$SIGN_KEYCHAIN" --sign "GoViet Dev" "$APP"
  echo "✓ Xong: $APP (ký bằng chứng chỉ GoViet Dev)"
else
  codesign --force --options runtime --sign - "$APP"
  echo "✓ Xong: $APP (ký ad-hoc — chạy ./make-cert.sh để không phải cấp lại quyền mỗi lần build)"
fi
