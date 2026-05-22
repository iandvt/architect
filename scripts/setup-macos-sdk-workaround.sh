#!/bin/sh

# Work around Zig 0.15.2 failing to link against the macOS 26.4 SDK family,
# whose top-level libSystem.tbd no longer advertises arm64-macos.
# Upstream tracker: https://codeberg.org/ziglang/zig/issues/31756
#
# Remove this once Architect no longer uses Zig 0.15.2, or once Zig's Darwin
# SDK discovery/linker handles the arm64e-only stub layout correctly.

legacy_sdk="${ARCHITECT_MACOS_SDK_WORKAROUND_LEGACY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
default_stub="${ARCHITECT_MACOS_SDK_WORKAROUND_DEFAULT_STUB:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib/libSystem.tbd}"

if [ ! -d "$legacy_sdk" ] || [ ! -f "$default_stub" ]; then
    return 0
fi

if sed -n '1,5p' "$default_stub" | grep -q 'arm64-macos'; then
    return 0
fi

project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
workaround_root="${ARCHITECT_MACOS_SDK_WORKAROUND_ROOT:-$project_root/.tmp/macos-sdk-workaround}"
bin_dir="$workaround_root/bin"
developer_dir="$workaround_root/developer"
developer_bin_dir="$developer_dir/usr/bin"
sdk_link="$developer_dir/SDKs/MacOSX.sdk"
platform_macos_sdk="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
platform_iphoneos_sdk="$developer_dir/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
platform_iphonesimulator_sdk="$developer_dir/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

mkdir -p \
    "$bin_dir" \
    "$developer_dir/SDKs" \
    "$developer_bin_dir" \
    "$developer_dir/Platforms/MacOSX.platform/Developer/SDKs" \
    "$developer_dir/Platforms/iPhoneOS.platform/Developer/SDKs" \
    "$developer_dir/Platforms/iPhoneSimulator.platform/Developer/SDKs"
ln -sfn "$legacy_sdk" "$sdk_link"
ln -sfn "$legacy_sdk" "$platform_macos_sdk"
ln -sfn "$legacy_sdk" "$platform_iphoneos_sdk"
ln -sfn "$legacy_sdk" "$platform_iphonesimulator_sdk"

xcrun_wrapper="$developer_bin_dir/xcrun"
cat > "$xcrun_wrapper" <<EOF
#!/bin/sh

if [ "\$1" = "--sdk" ] && [ "\$3" = "--show-sdk-path" ] && [ "\$#" -eq 3 ]; then
    case "\$2" in
        macosx)
            printf '%s\n' '$legacy_sdk'
            exit 0
            ;;
        iphoneos)
            printf '%s\n' '$platform_iphoneos_sdk'
            exit 0
            ;;
        iphonesimulator)
            printf '%s\n' '$platform_iphonesimulator_sdk'
            exit 0
            ;;
    esac
fi

exec env DEVELOPER_DIR= /usr/bin/xcrun "\$@"
EOF
chmod +x "$xcrun_wrapper"
ln -sfn "$xcrun_wrapper" "$bin_dir/xcrun"

case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) export PATH="$bin_dir:$PATH" ;;
esac

export DEVELOPER_DIR="$developer_dir"

echo "Applied Zig 0.15.2 macOS SDK workaround using $legacy_sdk"
