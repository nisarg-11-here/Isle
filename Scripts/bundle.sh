#!/bin/sh
# Builds the release binary, wraps it into Isle.app (no Dock icon), signs it ad hoc,
# installs it to ~/Applications, and starts it.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product Isle
APP=build/Isle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Isle "$APP/Contents/MacOS/Isle"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Isle</string>
  <key>CFBundleIdentifier</key><string>com.nisargchaudhary.isle</string>
  <key>CFBundleName</key><string>Isle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
pkill -x Isle 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Isle.app
ditto "$APP" ~/Applications/Isle.app
# -g: start in the background, do not take focus. Right after the copy, LaunchServices can
# refuse with error -600 until it registers the new bundle, so try again.
for i in 1 2 3 4 5 6 7 8 9 10; do
  open -g ~/Applications/Isle.app 2>/dev/null && break
  sleep 1
done
pgrep -x Isle >/dev/null || { echo "could not start Isle; run: open ~/Applications/Isle.app"; exit 1; }
echo "installed and started ~/Applications/Isle.app"
