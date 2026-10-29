#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
: "${TICKFIN_PREVIEW_DIR:?Set TICKFIN_PREVIEW_DIR to an external temporary preview directory}"
build_root="${TICKFIN_BUILD_ROOT:-$project_root/.build}"
export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
build_options=(--build-system native --disable-sandbox --scratch-path "$build_root" --cache-path "$build_root/cache" --config-path "$build_root/config" --security-path "$build_root/security")
binary_path="$(swift build "${build_options[@]}" -c release --show-bin-path)"
if [[ ! -f "$binary_path/StockCore.build/StockCore.swift.o" ]]; then
    printf '%s\n' '请先运行 bash scripts/build-app.sh' >&2
    exit 1
fi
sources=()
for source in Sources/StockBar/*.swift; do
    [[ "$source" == */StockBarMain.swift ]] || sources+=("$source")
done
mkdir -p "$TICKFIN_PREVIEW_DIR/runtime"
swiftc -parse-as-library -module-cache-path "$build_root/module-cache" -I "$binary_path/Modules" \
    "$binary_path"/StockCore.build/*.swift.o "${sources[@]}" \
    scripts/render-preview.swift -o "$TICKFIN_PREVIEW_DIR/render-preview"
TMPDIR="$TICKFIN_PREVIEW_DIR/runtime/" "$TICKFIN_PREVIEW_DIR/render-preview" "$TICKFIN_PREVIEW_DIR"
