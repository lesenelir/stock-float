#!/bin/sh
# Build a release binary and wrap it as build/StockFloat.app.
# Pass --universal to build for both Apple silicon and Intel; VERSION sets the bundle version.
set -eu

cd "$(dirname "$0")/.."
VERSION=${VERSION:-0.1.0}

ARCHS=""
if [ "${1:-}" = "--universal" ]; then
  ARCHS="--arch arm64 --arch x86_64"
fi
# $ARCHS is left unquoted on purpose so it splits into separate arguments.
swift build -c release $ARCHS
BIN_PATH=$(swift build -c release $ARCHS --show-bin-path)

APP=build/StockFloat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH/StockFloat" "$APP/Contents/MacOS/StockFloat"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>StockFloat</string>
  <key>CFBundleIdentifier</key>
  <string>com.lesenelir.stockfloat</string>
  <key>CFBundleName</key>
  <string>StockFloat</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
