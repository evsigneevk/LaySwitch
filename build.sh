#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LaySwitch"
BUNDLE_ID="com.layswitch.app"
SDK=$(xcrun --show-sdk-path --sdk macosx)
ARCH=$(uname -m)   # arm64 on Apple Silicon, x86_64 on Intel
ICON_SRC="Assets/AppIcon.png"
ICON_ICNS="Assets/AppIcon.icns"
STATUSBAR_ICON_1X="Assets/StatusBarIcon_18.png"
STATUSBAR_ICON_2X="Assets/StatusBarIcon_36.png"

SOURCES=(
    LaySwitch/App/AppDelegate.swift
    LaySwitch/InputSource/InputSourceManager.swift
    LaySwitch/Storage/LayoutStore.swift
    LaySwitch/Focus/AppFocusMonitor.swift
    LaySwitch/LoginItem/LoginItemManager.swift
    LaySwitch/UI/StatusBarController.swift
)

# ── Icon ──────────────────────────────────────────────────────────────────────

echo "→ Building icon..."
rm -rf "${ICON_ICNS}"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
    size="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$size" "$size" --setProperty format png "$ICON_SRC" \
        --out "$ICONSET/${name}.png" &>/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
rm -rf "$(dirname "$ICONSET")"

# ── App bundle ────────────────────────────────────────────────────────────────

echo "→ Cleaning..."
rm -rf "${APP_NAME}.app"

echo "→ Creating bundle structure..."
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

echo "→ Compiling..."
swiftc \
    -target "${ARCH}-apple-macos15.0" \
    -sdk "${SDK}" \
    -O \
    -framework Carbon \
    -framework AppKit \
    "${SOURCES[@]}" \
    -o "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

echo "→ Copying resources..."
cp "$ICON_ICNS" "${APP_NAME}.app/Contents/Resources/AppIcon.icns"
cp "$STATUSBAR_ICON_1X" "${APP_NAME}.app/Contents/Resources/StatusBarIcon.png"
cp "$STATUSBAR_ICON_2X" "${APP_NAME}.app/Contents/Resources/StatusBarIcon@2x.png"

echo "→ Writing Info.plist..."
cat > "${APP_NAME}.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - "${APP_NAME}.app"

echo "✓ Built ${APP_NAME}.app"
echo ""
echo "To install: make install"
