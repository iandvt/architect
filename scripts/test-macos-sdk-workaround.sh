#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
legacy_sdk=${ARCHITECT_MACOS_SDK_WORKAROUND_LEGACY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}
default_stub=${ARCHITECT_MACOS_SDK_WORKAROUND_DEFAULT_STUB:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib/libSystem.tbd}

if [[ ! -d "$legacy_sdk" || ! -f "$default_stub" ]]; then
    echo "skip: macOS SDK workaround prerequisites are not present"
    exit 0
fi

if sed -n '1,5p' "$default_stub" | grep -q 'arm64-macos'; then
    echo "skip: default macOS SDK already advertises arm64-macos"
    exit 0
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/architect-sdk-workaround-test.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

export ARCHITECT_MACOS_SDK_WORKAROUND_ROOT="$tmp_root"

# shellcheck disable=SC1091
. "$project_root/scripts/setup-macos-sdk-workaround.sh" >/dev/null

expected_developer_dir="$tmp_root/developer"
if [[ "${DEVELOPER_DIR:-}" != "$expected_developer_dir" ]]; then
    echo "expected DEVELOPER_DIR=$expected_developer_dir, got ${DEVELOPER_DIR:-unset}" >&2
    exit 1
fi

assert_link() {
    local link_path=$1
    if [[ ! -L "$link_path" ]]; then
        echo "missing SDK symlink: $link_path" >&2
        exit 1
    fi
    local target
    target=$(readlink "$link_path")
    if [[ "$target" != "$legacy_sdk" ]]; then
        echo "expected $link_path -> $legacy_sdk, got $target" >&2
        exit 1
    fi
}

assert_xcrun_sdk() {
    local sdk_name=$1
    local expected_path=$2
    local actual_path
    actual_path=$(xcrun --sdk "$sdk_name" --show-sdk-path)
    if [[ "$actual_path" != "$expected_path" ]]; then
        echo "expected xcrun $sdk_name path $expected_path, got $actual_path" >&2
        exit 1
    fi
}

assert_link "$expected_developer_dir/SDKs/MacOSX.sdk"
assert_link "$expected_developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
assert_link "$expected_developer_dir/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
assert_link "$expected_developer_dir/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

assert_xcrun_sdk "macosx" "$legacy_sdk"
assert_xcrun_sdk "iphoneos" "$expected_developer_dir/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
assert_xcrun_sdk "iphonesimulator" "$expected_developer_dir/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
