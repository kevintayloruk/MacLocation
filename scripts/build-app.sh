#!/usr/bin/env bash
# Builds MacLocation.app into ./build.
#
#   scripts/build-app.sh             # build for this Mac's architecture
#   UNIVERSAL=1 scripts/build-app.sh # arm64 + x86_64 (needs full Xcode)
#   scripts/build-app.sh --install   # also copy to /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

APP="build/MacLocation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacLocation" "$APP/Contents/MacOS/MacLocation"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS will run it locally and allow Launch at Login.
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "MacLocation"' >/dev/null 2>&1 || true
    rm -rf "/Applications/MacLocation.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/MacLocation.app"
    open /Applications/MacLocation.app
fi
