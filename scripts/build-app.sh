#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
build_root="${TICKFIN_BUILD_ROOT:-$project_root/.build}"
export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
build_options=(--build-system native --disable-sandbox --scratch-path "$build_root" --cache-path "$build_root/cache" --config-path "$build_root/config" --security-path "$build_root/security")
swift build "${build_options[@]}" -c release --product StockBar
binary_path="$(swift build "${build_options[@]}" -c release --show-bin-path)"
app_path="${TICKFIN_APP_PATH:-$project_root/dist/Tickfin.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path/StockBar" "$app_path/Contents/MacOS/StockBar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
cp "$project_root/Resources/MenuBarTemplate.png" "$app_path/Contents/Resources/MenuBarTemplate.png"
cp "$project_root/Resources/MenuBarTemplate@2x.png" "$app_path/Contents/Resources/MenuBarTemplate@2x.png"
chmod 755 "$app_path/Contents/MacOS/StockBar"
codesign --force --sign - --identifier local.stockbar.app "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
printf '%s\n' "$app_path"
