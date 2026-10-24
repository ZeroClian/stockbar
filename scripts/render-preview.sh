#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
build_root="$(swift build --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --show-bin-path)"
if [[ ! -f "$build_root/StockCore.build/StockCore.swift.o" ]]; then
    printf '%s\n' '请先运行 bash scripts/build-app.sh' >&2
    exit 1
fi
swiftc -parse-as-library -module-cache-path .build/module-cache -I "$build_root/Modules" \
    "$build_root/StockCore.build/StockCore.swift.o" \
    Sources/StockBar/AppStore.swift Sources/StockBar/QuoteService.swift \
    Sources/StockBar/NotificationService.swift Sources/StockBar/Styles.swift \
    Sources/StockBar/PanelView.swift Sources/StockBar/Editors.swift \
    scripts/render-preview.swift -o .build/render-preview
.build/render-preview docs/verification/native-preview
