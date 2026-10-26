#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
case "${1:-}" in
    "") bash scripts/build-app.sh ;;
    --skip-build) ;;
    *) printf '%s\n' 'Usage: bash scripts/package-release.sh [--skip-build]' >&2; exit 2 ;;
esac

app_path="${TICKFIN_APP_PATH:-$project_root/dist/Tickfin.app}"
release_dir="${TICKFIN_RELEASE_DIR:-$project_root/dist}"
work_root="${TICKFIN_BUILD_ROOT:-$project_root/.build}"
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
stem="Tickfin-$version-$architecture"
mkdir -p "$work_root/release-staging.noindex" "$release_dir"
stage="$(mktemp -d "$work_root/release-staging.noindex/stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_path" "$stage/Tickfin.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp docs/INSTALL.md "$stage/安装说明.md"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_dir/$stem.zip"
hdiutil create -volname "Tickfin $version" -srcfolder "$stage" -format UDZO -ov "$release_dir/$stem.dmg"
hdiutil verify "$release_dir/$stem.dmg"
unzip -tq "$release_dir/$stem.zip"
(
    cd "$release_dir"
    shasum -a 256 "$stem.dmg" "$stem.zip" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
printf 'Release files: %s/%s.{dmg,zip}, %s/SHA256SUMS.txt\n' "$release_dir" "$stem" "$release_dir"
