#!/bin/bash
# Builds "Glass Notes.app" (universal: Apple Silicon + Intel) into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Glass Notes.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compiling…"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" Sources/*.swift -o "build/GlassNotes-$arch"
done
lipo -create build/GlassNotes-arm64 build/GlassNotes-x86_64 -output "$APP/Contents/MacOS/GlassNotes"
rm build/GlassNotes-arm64 build/GlassNotes-x86_64

cp Info.plist "$APP/Contents/"
cp assets/AppIcon.icns "$APP/Contents/Resources/"

echo "→ Signing (ad-hoc)…"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "→ Zipping for sharing…"
(cd build && ditto -c -k --norsrc --noextattr --noacl --keepParent "Glass Notes.app" Glass-Notes-macOS.zip)

echo "✓ Done: $APP and build/Glass-Notes-macOS.zip"
