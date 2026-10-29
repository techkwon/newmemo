#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/새 메모.app"
EXT="$APP/Contents/PlugIns/NewMemoFinder.appex"
ARCH="$(uname -m)"
SIGN_IDENTITY="${NEWMEMO_SIGN_IDENTITY:--}"
mkdir -p build
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/FinderExtension-Info.plist "$EXT/Contents/Info.plist"
swiftc -swift-version 5 -warnings-as-errors -O -target "$ARCH-apple-macos13.0" \
  -module-name NewMemo -framework AppKit -framework FinderSync -framework ImageIO \
  Sources/Core/*.swift Sources/App/*.swift -o "$APP/Contents/MacOS/NewMemo"
swiftc -swift-version 5 -warnings-as-errors -O -target "$ARCH-apple-macos13.0" \
  -module-name NewMemoFinder -application-extension -framework AppKit -framework FinderSync \
  Sources/Core/*.swift Sources/FinderExtension/*.swift -o "$EXT/Contents/MacOS/NewMemoFinder"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$SIGN_IDENTITY" --options runtime \
  --entitlements Resources/FinderExtension.entitlements "$EXT"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" "$EXT/Contents/Info.plist"
echo "빌드 완료: $APP"
