#!/bin/bash
# Builds "YK Cleaner.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/YK Cleaner.app"
mkdir -p build

# Workaround for a known broken Command Line Tools install: a stale
# usr/include/swift/module.modulemap redefines SwiftBridging. Hide it via a VFS overlay.
SWIFT_FLAGS=()
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [ -f "$STALE" ] && [ -f "$(dirname "$STALE")/bridging.modulemap" ]; then
  : > build/empty.modulemap
  cat > build/vfs.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory",
  "name": "$(dirname "$STALE")", "contents": [ { "type": "file",
  "name": "module.modulemap", "external-contents": "$PWD/build/empty.modulemap" } ] } ] }
YAML
  SWIFT_FLAGS=(-vfsoverlay build/vfs.yaml -Xcc -ivfsoverlay -Xcc build/vfs.yaml)
fi

# UNIVERSAL=1 builds for both Apple Silicon and Intel (used for releases).
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(arm64 x86_64); else ARCHS=("$(uname -m)"); fi
SLICES=()
for arch in "${ARCHS[@]}"; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos14.0" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} \
    -o "build/YKCleaner-$arch" Sources/YKCleaner/*.swift
  SLICES+=("build/YKCleaner-$arch")
done
lipo -create "${SLICES[@]}" -output build/YKCleaner
rm -f "${SLICES[@]}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv build/YKCleaner "$APP/Contents/MacOS/YKCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Version: VERSION file (marketing version) + git commit count (build number)
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# App icon
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} Scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon-1024.png

codesign --force --deep --sign - "$APP"
echo "Built: $APP (v$VERSION, build $BUILD)"
