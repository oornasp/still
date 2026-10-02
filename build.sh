#!/bin/zsh
# Builds Still.app with nothing but the Xcode Command Line Tools.
#
#   ./build.sh            build into ./build/Still.app
#   ./build.sh install    build, then copy to /Applications and launch
#   ./build.sh run        build, then launch from ./build
#   UNIVERSAL=1 ./build.sh   fat binary (arm64 + x86_64)
set -euo pipefail
cd "${0:A:h}"

APP="build/Still.app"
BIN="$APP/Contents/MacOS/Still"
MIN_OS="14.0"
SDK="$(xcrun --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {
  swiftc -O -wmo -swift-version 5 \
    -target "$1-apple-macos$MIN_OS" -sdk "$SDK" \
    -Xlinker -dead_strip \
    Sources/*.swift -o "$2"
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  compile arm64 build/Still-arm64
  compile x86_64 build/Still-x86_64
  lipo -create build/Still-arm64 build/Still-x86_64 -output "$BIN"
  rm build/Still-arm64 build/Still-x86_64
else
  compile "$(uname -m)" "$BIN"
fi
strip -x "$BIN"

[[ -f Resources/AppIcon.icns ]] || swift scripts/make_icon.swift Resources
[[ -f Resources/Chime-Rest.caf ]] || swift scripts/make_sounds.swift Resources

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/*.caf "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --sign - --options runtime "$APP" >/dev/null

echo "Built $APP ($(du -sh "$APP" | cut -f1), binary $(du -h "$BIN" | cut -f1))"

case "${1:-}" in
  install)
    pkill -x Still 2>/dev/null || true
    rm -rf /Applications/Still.app
    cp -R "$APP" /Applications/
    open /Applications/Still.app
    echo "Installed to /Applications/Still.app"
    ;;
  run)
    pkill -x Still 2>/dev/null || true
    open "$APP"
    ;;
esac
