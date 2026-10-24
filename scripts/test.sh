#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build-core/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build-core/module-cache"
developer_root="$(xcode-select -p)"
testing_frameworks="$developer_root/Library/Developer/Frameworks"
if [ ! -d "$testing_frameworks/Testing.framework" ]; then
    testing_frameworks="$developer_root/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
swift test --build-system native --disable-sandbox --disable-xctest \
    --scratch-path .build-core --cache-path .build-core/cache \
    --config-path .build-core/config --security-path .build-core/security \
    -Xswiftc -F -Xswiftc "$testing_frameworks" \
    -Xlinker "-F$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks" "$@"
