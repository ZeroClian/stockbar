#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
case "${1:-}" in
    "") bash scripts/build-app.sh ;;
    --skip-build) ;;
    *) printf '%s\n' 'Usage: bash scripts/package-release.sh [--skip-build]' >&2; exit 2 ;;
esac

app_path="$project_root/dist/自选股.app"
codesign --verify --strict "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
architecture="$(lipo -archs "$app_path/Contents/MacOS/StockBar")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'Expected a numeric major.minor.patch version.' >&2
    exit 1
fi
case "$architecture" in
    arm64|x86_64) ;;
    *) printf '%s\n' 'Expected one supported architecture; do not mislabel a universal build.' >&2; exit 1 ;;
esac
stem="StockBar-$version-$architecture"
mkdir -p .build dist
stage="$(mktemp -d "$project_root/.build/release-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_path" "$stage/自选股.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp docs/INSTALL.md "$stage/安装说明.md"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "dist/$stem.zip"
hdiutil create -volname "StockBar $version" -srcfolder "$stage" -format UDZO -ov "dist/$stem.dmg"
hdiutil verify "dist/$stem.dmg"
unzip -tq "dist/$stem.zip"
(
    cd dist
    shasum -a 256 "$stem.dmg" "$stem.zip" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
printf 'Release files: dist/%s.{dmg,zip}, dist/SHA256SUMS.txt\n' "$stem"
