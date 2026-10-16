#!/bin/bash
# Builds a Developer ID-signed, Apple-notarized Bare.dmg and publishes it as a GitHub release.
#
# One-time setup (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials bare-notary --apple-id <your Apple ID> --team-id VW98Z8698B
#
# Then:  ./release.sh            (uses the version in Resources/Info.plist)
#        ./release.sh --no-upload  (build and notarize only)
set -euo pipefail
cd "$(dirname "$0")"

APP=Bare
IDENTITY=${IDENTITY:-"Developer ID Application: Manuel Cabeza (VW98Z8698B)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-bare-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DIST=dist
DMG="$DIST/$APP.dmg"
VERSIONED_DMG="$DIST/$APP-$VERSION.dmg"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "No notarytool profile named '$NOTARY_PROFILE'. Run the one-time setup at the top of this file."
    exit 1
}

echo "▸ Building $APP $VERSION"
IDENTITY="$IDENTITY" ./build.sh
rm -rf "$DIST" && mkdir -p "$DIST"

echo "▸ Notarizing the app"
ditto -c -k --keepParent "build/$APP.app" "$DIST/$APP.zip"
xcrun notarytool submit "$DIST/$APP.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "build/$APP.app"
rm "$DIST/$APP.zip"

echo "▸ Making the disk image"
STAGE=$(mktemp -d)
cp -R "build/$APP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "▸ Notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
cp "$DMG" "$VERSIONED_DMG"
echo "✓ $DMG"

if [[ "${1:-}" == "--no-upload" ]]; then exit 0; fi

echo "▸ Publishing v$VERSION on GitHub"
# Bare.dmg (unversioned) is what the website's download button points at:
# https://github.com/orlandoascanio/Bare/releases/latest/download/Bare.dmg
gh release create "v$VERSION" "$DMG" "$VERSIONED_DMG" \
    --title "Bare $VERSION" \
    --notes "Download **Bare.dmg**, open it, and drag Bare to Applications. Signed and notarized by Apple. Requires macOS 13 or later."
echo "✓ Released v$VERSION"
