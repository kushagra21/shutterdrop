#!/bin/zsh
# Builds Shutterdrop.app from the Swift package: release binary, Info.plist
# (needed for the Local Network permission prompt) and an ad-hoc signature.
#
# Usage: scripts/build-app.sh [output-dir]   (default: build/)
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build}"
app="$out/Shutterdrop.app"

swift build -c release --product Shutterdrop
bin="$(swift build -c release --product Shutterdrop --show-bin-path)/Shutterdrop"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Shutterdrop"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Shutterdrop</string>
    <key>CFBundleDisplayName</key><string>Shutterdrop</string>
    <key>CFBundleIdentifier</key><string>app.shutterdrop.Shutterdrop</string>
    <key>CFBundleExecutable</key><string>Shutterdrop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Shutterdrop finds your camera on the local network and copies photos from it.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
