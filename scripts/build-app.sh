#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
build_options=(--build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
swift build "${build_options[@]}" -c release --product StockBar
binary_path="$(swift build "${build_options[@]}" -c release --show-bin-path)"
app_path="$project_root/dist/Tickfin.app"
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
