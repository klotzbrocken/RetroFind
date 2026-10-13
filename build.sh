#!/bin/bash
# Builds build/RetroFind.app – universal (arm64 + x86_64).
# Default: signed with the local "Apple Development" identity (or ad-hoc).
# HARDENED=1 → "Developer ID Application" + hardened runtime + timestamp (prerequisite for notarization, see release.sh).
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-1.2}"
swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -E "error|Build" | tail -20
APP="build/RetroFind.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MLFinder; cp "$BIN" "$APP/Contents/MacOS/RetroFind"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RetroFind</string>
<key>CFBundleDisplayName</key><string>RetroFind</string>
<key>CFBundleIdentifier</key><string>de.maik.RetroFind</string>
<key>CFBundleExecutable</key><string>RetroFind</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Maik Klotz. GPL-3.0.</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
<key>NSDesktopFolderUsageDescription</key><string>RetroFind shows your files. / RetroFind zeigt deine Dateien an.</string>
<key>NSDocumentsFolderUsageDescription</key><string>RetroFind shows your files. / RetroFind zeigt deine Dateien an.</string>
<key>NSDownloadsFolderUsageDescription</key><string>RetroFind shows your files. / RetroFind zeigt deine Dateien an.</string>
<key>NSRemovableVolumesUsageDescription</key><string>RetroFind shows your disks. / RetroFind zeigt deine Datenträger an.</string>
<key>NSNetworkVolumesUsageDescription</key><string>RetroFind shows network volumes. / RetroFind zeigt Netzwerkvolumes an.</string>
<key>NSLocalNetworkUsageDescription</key><string>RetroFind finds shared computers on your network. / RetroFind findet freigegebene Computer im Netzwerk.</string>
<key>NSBonjourServices</key><array><string>_smb._tcp</string><string>_afpovertcp._tcp</string></array>
</dict></plist>
P
KIND="Apple Development"; [ -n "$HARDENED" ] && KIND="Developer ID Application"
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o "\"$KIND[^\"]*\"" | head -1 | tr -d '"')}"
if [ -n "$HARDENED" ]; then
  codesign --force --timestamp --options runtime --sign "$ID" "$APP" && echo "signed (hardened runtime): $ID"
elif [ -n "$ID" ]; then codesign --force --sign "$ID" "$APP" && echo "signed: $ID" || codesign --force --sign - "$APP"
else codesign --force --sign - "$APP" >/dev/null 2>&1; echo "ad-hoc signed"; fi
echo "OK: $APP"
