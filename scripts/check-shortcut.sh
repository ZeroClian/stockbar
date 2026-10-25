#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
build_root="$(swift build --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --show-bin-path)"
swiftc -parse-as-library -module-cache-path .build/module-cache -I "$build_root/Modules" \
    "$build_root"/StockCore.build/*.swift.o Sources/StockBar/GlobalShortcutService.swift \
    scripts/check-shortcut.swift -o .build/check-shortcut
.build/check-shortcut
