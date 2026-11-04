#!/bin/bash
# Builds a universal release and packages it for download.
#   Scripts/release.sh            → dist/YK-Cleaner-<version>.dmg and .zip
#   Scripts/release.sh --publish  → also tags v<version>, pushes the tag and
#                                   creates a GitHub release with both files (needs `gh`).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="YK-Cleaner-$VERSION"
APP="build/YK Cleaner.app"

UNIVERSAL=1 ./build-app.sh

rm -rf dist && mkdir -p dist

# ZIP (keeps the bundle's metadata and signature intact)
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$NAME.zip"

# DMG with an Applications shortcut for drag-to-install
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "YK Cleaner $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg" >/dev/null
rm -rf "$STAGE"

(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "Packaged:"; ls -lh dist

if [ "${1:-}" = "--publish" ]; then
  TAG="v$VERSION"
  # Release notes = this version's section of CHANGELOG.md
  NOTES="$(awk -v v="$VERSION" '/^## /{p = index($0, v) > 0; next} p' CHANGELOG.md)"
  git rev-parse "$TAG" >/dev/null 2>&1 || git tag -a "$TAG" -m "YK Cleaner $VERSION"
  git push origin "$TAG"
  gh release create "$TAG" "dist/$NAME.dmg" "dist/$NAME.zip" dist/SHA256SUMS.txt \
    --title "YK Cleaner $VERSION" --notes "$NOTES"
fi
