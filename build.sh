#!/bin/bash
# Builds Bare.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP=Bare
OUT="build/$APP.app"

ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}"; then
    echo "Universal build failed, building for this Mac only…"
    ARCHS=()
    swift build -c release
fi
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$APP"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
# IDENTITY="Developer ID Application: …" signs for distribution (see release.sh); default is ad-hoc.
if [[ -n "${IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$OUT"
else
    codesign --force --sign - "$OUT"
fi

echo "Built $OUT"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP" 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/$APP.app"
    cp -R "$OUT" /Applications/
    open "/Applications/$APP.app"
    echo "Installed to /Applications/$APP.app"
fi
