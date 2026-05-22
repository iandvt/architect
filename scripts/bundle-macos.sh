#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <executable> <output-dir> [architect-mcp-executable] [--with-mcp <path>] [--debug] [--unsigned] [--app-name <name>]"
    exit 1
fi

EXECUTABLE="$1"
OUTPUT_DIR="$2"
shift 2

MCP_EXECUTABLE=""
INCLUDE_MCP=false
DEBUG_MODE=false
SIGN_APP=true
APP_NAME="Architect (Stable)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --unsigned)
            SIGN_APP=false
            shift
            ;;
        --with-mcp)
            if [[ $# -lt 2 ]]; then
                echo "--with-mcp requires a value"
                exit 1
            fi
            INCLUDE_MCP=true
            MCP_EXECUTABLE="$2"
            shift 2
            ;;
        --with-mcp=*)
            INCLUDE_MCP=true
            MCP_EXECUTABLE="${1#--with-mcp=}"
            shift
            ;;
        --app-name)
            if [[ $# -lt 2 ]]; then
                echo "--app-name requires a value"
                exit 1
            fi
            APP_NAME="$2"
            shift 2
            ;;
        --app-name=*)
            APP_NAME="${1#--app-name=}"
            shift
            ;;
        --*)
            echo "Unknown flag: $1"
            exit 1
            ;;
        *)
            if [[ -z "$MCP_EXECUTABLE" ]]; then
                INCLUDE_MCP=true
                MCP_EXECUTABLE="$1"
                shift
            else
                echo "Unknown argument: $1"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$APP_NAME" ]]; then
    echo "Error: app name must not be empty"
    exit 1
fi

if [[ "$INCLUDE_MCP" == true && -z "$MCP_EXECUTABLE" ]]; then
    echo "Error: MCP helper path must not be empty"
    exit 1
fi

BUNDLE_IDENTIFIER="com.forketyfork.architect"
app_name_pattern='^Architect \(([^)]+)\)$'
if [[ ! "$APP_NAME" =~ $app_name_pattern ]]; then
    echo "Error: app name must be in the form 'Architect (<channel>)'"
    exit 1
fi

bundle_suffix=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')
bundle_suffix="${bundle_suffix#-}"
bundle_suffix="${bundle_suffix%-}"
if [[ -n "$bundle_suffix" ]]; then
    BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER.$bundle_suffix"
fi

APP_DIR="$OUTPUT_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LIB_DIR="$MACOS_DIR/lib"
SHARE_DIR="$CONTENTS_DIR/share/architect"
ICON_SOURCE="assets/macos/Architect.icns"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ "$SIGN_APP" == true ]]; then
    if [[ "$DEBUG_MODE" == true ]]; then
        ENTITLEMENTS="$REPO_ROOT/macos/ArchitectDebug.entitlements"
    else
        ENTITLEMENTS="$REPO_ROOT/macos/Architect.entitlements"
    fi
fi

echo "Bundling macOS application: $EXECUTABLE -> $APP_DIR"
if [[ "$INCLUDE_MCP" == true ]]; then
    echo "Including MCP helper: $MCP_EXECUTABLE"

    if [[ ! -f "$MCP_EXECUTABLE" ]]; then
        echo "Error: architect-mcp executable not found: $MCP_EXECUTABLE"
        exit 1
    fi
else
    echo "MCP helper: not bundled"
fi

rm -rf "$APP_DIR"
mkdir -p "$LIB_DIR" "$RESOURCES_DIR" "$SHARE_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>architect</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>A program running in Architect would like to use AppleScript.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>A program running in Architect would like to use Bluetooth.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>A program running in Architect would like to access your Calendar.</string>
    <key>NSCameraUsageDescription</key>
    <string>A program running in Architect would like to use the camera.</string>
    <key>NSContactsUsageDescription</key>
    <string>A program running in Architect would like to access your Contacts.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>A program running in Architect would like to access the local network.</string>
    <key>NSLocationUsageDescription</key>
    <string>A program running in Architect would like to access your location.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>A program running in Architect would like to use your microphone.</string>
    <key>NSMotionUsageDescription</key>
    <string>A program running in Architect would like to access motion data.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>A program running in Architect would like to access your Photo Library.</string>
    <key>NSRemindersUsageDescription</key>
    <string>A program running in Architect would like to access your reminders.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>A program running in Architect would like to use speech recognition.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>A program running in Architect requires elevated privileges.</string>
  </dict>
</plist>
EOF

if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/${APP_NAME}.icns"
    echo "Added app icon: $ICON_SOURCE"
else
    echo "Icon not found at $ICON_SOURCE (add an .icns file there to bundle it)"
fi

# Copy the binary as the main executable (dylibs use @executable_path/lib/)
cp "$EXECUTABLE" "$MACOS_DIR/architect"
chmod +x "$MACOS_DIR/architect"
if [[ "$INCLUDE_MCP" == true ]]; then
    cp "$MCP_EXECUTABLE" "$MACOS_DIR/architect-mcp"
    chmod +x "$MACOS_DIR/architect-mcp"
fi

seen_list=""
queue=""

enqueue() {
    local dep="$1"
    if [[ -z "$dep" ]]; then
        return
    fi

    if [[ ! -f "$dep" ]]; then
        echo "Warning: $dep not found, skipping"
        return
    fi

    if printf '%s\n' "$seen_list" | grep -Fxq "$dep"; then
        return
    fi

    seen_list="$seen_list
$dep"
    if [[ -z "$queue" ]]; then
        queue="$dep"
    else
        queue="$queue
$dep"
    fi
}

remove_signature_if_present() {
    local file="$1"
    if codesign -dv "$file" >/dev/null 2>&1; then
        echo "Removing embedded signature from $(basename "$file")..."
        codesign --remove-signature "$file"
    fi
}

nix_deps_for() {
    local file="$1"
    otool -L "$file" | awk '/^[[:space:]]/ {print $1}' | grep '^/nix/store' || true
}

patch_binary_deps() {
    local binary="$1"
    local label="$2"
    local deps original name

    deps=$(nix_deps_for "$binary")
    if [[ -z "$deps" ]]; then
        echo "No Nix store dependencies found in $label"
        return
    fi

    while IFS= read -r original; do
        [[ -z "$original" ]] && continue
        name=$(basename "$original")
        install_name_tool -change "$original" "@executable_path/lib/$name" "$binary"
    done <<< "$deps"
}

echo "Analyzing dynamic library dependencies..."
initial_deps=$(
    {
        nix_deps_for "$EXECUTABLE"
        if [[ "$INCLUDE_MCP" == true ]]; then
            nix_deps_for "$MCP_EXECUTABLE"
        fi
    } | sort -u
)

# Use a flag instead of early return: bundling must still finish even without Nix deps
skip_lib_patching=false
if [[ -z "$initial_deps" ]]; then
    echo "No Nix store dependencies found"
    skip_lib_patching=true
fi

if [[ "$skip_lib_patching" != true ]]; then
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        enqueue "$dep"
    done <<< "$initial_deps"

    echo "Found dependencies:"
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        printf '  %s\n' "$dep"
    done <<< "$initial_deps"

    while [[ -n "$queue" ]]; do
        if [[ "$queue" == *$'\n'* ]]; then
            lib_path="${queue%%$'\n'*}"
            queue="${queue#*$'\n'}"
        else
            lib_path="$queue"
            queue=""
        fi

        lib_name=$(basename "$lib_path")
        dest="$LIB_DIR/$lib_name"

        if [[ ! -f "$dest" ]]; then
            echo "Copying $lib_name..."
            cp "$lib_path" "$dest"
            chmod 644 "$dest"
        fi

        install_name_tool -id "@executable_path/lib/$lib_name" "$dest"

        nested_list=$(nix_deps_for "$lib_path")
        while IFS= read -r nested_dep; do
            [[ -z "$nested_dep" ]] && continue
            nested_name=$(basename "$nested_dep")
            install_name_tool -change "$nested_dep" "@executable_path/lib/$nested_name" "$dest"
            enqueue "$nested_dep"
        done <<< "$nested_list"
    done

    patch_binary_deps "$MACOS_DIR/architect" "architect"
    if [[ "$INCLUDE_MCP" == true ]]; then
        patch_binary_deps "$MACOS_DIR/architect-mcp" "architect-mcp"
    fi

    echo ""
    echo "Verifying final dependencies..."
    if otool -L "$MACOS_DIR/architect" | grep -q '/nix/store'; then
        echo "Warning: Nix store references remain in architect binary"
        otool -L "$MACOS_DIR/architect" | grep '/nix/store'
    fi
    if [[ "$INCLUDE_MCP" == true ]] && otool -L "$MACOS_DIR/architect-mcp" | grep -q '/nix/store'; then
        echo "Warning: Nix store references remain in architect-mcp binary"
        otool -L "$MACOS_DIR/architect-mcp" | grep '/nix/store'
    fi

    remaining=0
    shopt -s nullglob
    for file in "$LIB_DIR"/*.dylib; do
        if otool -L "$file" | grep -q '/nix/store'; then
            echo "Warning: Nix store references remain in $file"
            otool -L "$file" | grep '/nix/store'
            remaining=1
        fi
    done
    shopt -u nullglob

    if [[ $remaining -eq 0 ]]; then
        echo "All bundled libraries patched to use @executable_path/lib"
    fi
fi

if [[ "$SIGN_APP" == true ]]; then
    echo ""
    echo "Signing application bundle with entitlements..."
    if [[ ! -f "$ENTITLEMENTS" ]]; then
        echo "Error: Entitlements file not found: $ENTITLEMENTS"
        exit 1
    fi

    shopt -s nullglob
    for lib in "$LIB_DIR"/*.dylib; do
        echo "Signing $(basename "$lib")..."
        codesign --force --sign - "$lib"
    done
    shopt -u nullglob

    if [[ "$INCLUDE_MCP" == true ]]; then
        echo "Signing architect-mcp..."
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS_DIR/architect-mcp"
    fi

    echo "Signing architect..."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS_DIR/architect"

    echo "Signing ${APP_NAME}.app..."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"

    echo "Code signing complete."
else
    echo ""
    echo "Removing embedded signatures (--unsigned)..."
    remove_signature_if_present "$MACOS_DIR/architect"
    if [[ "$INCLUDE_MCP" == true ]]; then
        remove_signature_if_present "$MACOS_DIR/architect-mcp"
    fi
    shopt -s nullglob
    for lib in "$LIB_DIR"/*.dylib; do
        remove_signature_if_present "$lib"
    done
    shopt -u nullglob
    echo "Skipping code signing (--unsigned)."
fi

echo ""
echo "Bundle complete! Structure:"
find "$OUTPUT_DIR" -type f

echo ""
echo "To distribute, package the entire directory:"
echo "  cd $OUTPUT_DIR && tar -czf architect-macos.tar.gz \"${APP_NAME}.app\""
