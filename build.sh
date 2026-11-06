#!/bin/bash
# Compila DroidBridge e crea DroidBridge.app nella cartella corrente.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="DroidBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DroidBridge "$APP/Contents/MacOS/DroidBridge"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DroidBridge</string>
    <key>CFBundleIdentifier</key><string>com.example.droidbridge</string>
    <key>CFBundleName</key><string>DroidBridge</string>
    <key>CFBundleDisplayName</key><string>DroidBridge</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Davide Bossi</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Icona dell'app: ricava AppIcon.icns da Resources/AppIcon.png (1024x1024) con gli strumenti di macOS
if [ -f Resources/AppIcon.png ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

# Firma ad-hoc, sufficiente per usarla sul proprio Mac
codesign --force --deep --sign - "$APP"

# Aggiorna la data del pacchetto così Finder e Dock mostrano subito la nuova icona
touch "$APP"

echo "Fatto: $(pwd)/$APP"
echo "Apri con: open \"$APP\""
