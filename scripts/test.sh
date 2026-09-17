#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [[ "${PICKLINGO_USE_CLT:-0}" != "1" ]]; then
    exec swift test --enable-xctest --disable-swift-testing "$@"
fi

# Fallback for hosts where the standalone compiler works but xcodebuild is unavailable.
# XCTest is still required from an installed Xcode; this does not change system settings.
clt_dir="/Library/Developer/CommandLineTools"
xcode_dir="${PICKLINGO_XCODE_DIR:-/Applications/Xcode.app/Contents/Developer}"
platform_dir="$xcode_dir/Platforms/MacOSX.platform/Developer"
framework_dir="$platform_dir/Library/Frameworks"
library_dir="$platform_dir/usr/lib"
swift_bin="$clt_dir/usr/bin/swift"
flags=(
    -Xswiftc -F -Xswiftc "$framework_dir"
    -Xswiftc -I -Xswiftc "$library_dir"
    -Xlinker -F -Xlinker "$framework_dir"
    -Xlinker -L -Xlinker "$library_dir"
    -Xlinker -rpath -Xlinker "$framework_dir"
    -Xlinker -rpath -Xlinker "$library_dir"
)
DEVELOPER_DIR="$clt_dir" "$swift_bin" build --build-tests "${flags[@]}" "$@"
test_dir="$(DEVELOPER_DIR="$clt_dir" "$swift_bin" build --show-bin-path "$@")"
DEVELOPER_DIR="$clt_dir" "$platform_dir/Library/Xcode/Agents/xctest" "$test_dir/PickLingoPackageTests.xctest"
