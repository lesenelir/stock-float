#!/bin/sh
# Build a release binary and wrap it as build/StockFloat.app.
set -eu

cd "$(dirname "$0")/.."
swift build -c release

APP=build/StockFloat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/StockFloat "$APP/Contents/MacOS/StockFloat"

cat > "$APP/Contents/Info.plist" <<'EOF'
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
