#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test_root="${TICKFIN_TEST_ROOT:-$project_root/.build-core}"
export CLANG_MODULE_CACHE_PATH="$test_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_root/module-cache"
developer_root="$(xcode-select -p)"
testing_frameworks="$developer_root/Library/Developer/Frameworks"
if [ ! -d "$testing_frameworks/Testing.framework" ]; then
    testing_frameworks="$developer_root/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
swift test --build-system native --disable-sandbox --disable-xctest \
    --scratch-path "$test_root" --cache-path "$test_root/cache" \
    --config-path "$test_root/config" --security-path "$test_root/security" \
    -Xswiftc -F -Xswiftc "$testing_frameworks" \
    -Xlinker "-F$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks" "$@"
