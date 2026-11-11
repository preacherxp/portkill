#!/bin/sh
# Builds portkill.app (universal, ad-hoc signed) in the repo root.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
app=portkill.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/apple/Products/Release/portkill "$app/Contents/MacOS/portkill"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>portkill</string>
  <key>CFBundleIdentifier</key><string>com.preacherxp.portkill</string>
  <key>CFBundleName</key><string>portkill</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "Built $app"
