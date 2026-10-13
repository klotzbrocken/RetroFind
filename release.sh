#!/bin/bash
# Release: Developer ID signature + hardened runtime, notarize the app, build the DMG (signed, notarized, stapled).
# Notary profile (once): xcrun notarytool store-credentials Retromac --apple-id <ID> --team-id <TEAM>
# "./release.sh publish" additionally creates a GitHub release v<VERSION> with the DMG.
set -e
cd "$(dirname "$0")"
PROFILE="${NOTARY_PROFILE:-Retromac}"
export VERSION="${VERSION:-1.2}"
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}"
[ -n "$ID" ] || { echo "No 'Developer ID Application' certificate in the keychain."; exit 1; }
HARDENED=1 SIGN_ID="$ID" ./build.sh
APP="build/RetroFind.app"; DMG="build/RetroFind-$VERSION.dmg"; TMP=$(mktemp -d)
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Notarize app =="
ditto -c -k --keepParent "$APP" "$TMP/app.zip"
xcrun notarytool submit "$TMP/app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "== DMG =="
rm -f "$DMG"; mkdir "$TMP/dmg"; cp -R "$APP" "$TMP/dmg/"; ln -s /Applications "$TMP/dmg/Applications"
hdiutil create -volname "RetroFind" -srcfolder "$TMP/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
rm -rf "$TMP"; echo "DONE: $DMG"

if [ "$1" = "publish" ]; then
  gh release create "v$VERSION" "$DMG" --title "RetroFind $VERSION" --notes "Notarized DMG (Developer ID, hardened runtime, universal)."
fi
