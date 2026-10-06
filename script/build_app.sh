#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_config.sh"
CONFIGURATION="${1:-debug}"
ARCHITECTURE="${2:-native}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Expected debug or release" >&2; exit 2 ;; esac
case "$ARCHITECTURE" in native|universal) ;; *) echo "Expected native or universal" >&2; exit 2 ;; esac
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
BUILD_ARGS=(-c "$CONFIGURATION" --disable-sandbox --scratch-path "$ROOT_DIR/.build" --cache-path "$ROOT_DIR/.build/cache" -Xswiftc -module-cache-path -Xswiftc "$ROOT_DIR/.build/module-cache")
if [[ "$ARCHITECTURE" == universal ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
RESOURCE_BUNDLE="$BUILD_DIR/SteamGameLauncher_SteamGameLauncher.bundle"
DESTINATION_RESOURCES="$APP_BUNDLE/Contents/Resources/SteamGameLauncher_SteamGameLauncher.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    if [[ -d "$DESTINATION_RESOURCES" ]]; then
        BACKUP="$(mktemp -d "$ROOT_DIR/.build/resource-backup.XXXXXX")"
        mv "$DESTINATION_RESOURCES" "$BACKUP/Resources.archive"
    fi
    ditto "$RESOURCE_BUNDLE" "$DESTINATION_RESOURCES"
fi
cp "$ROOT_DIR/Sources/SteamGameLauncher/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
python3 - "$APP_BUNDLE/Contents/Info.plist" "$APP_EXECUTABLE" "$BUNDLE_ID" "$APP_DISPLAY_NAME" "$APP_VERSION" "$APP_BUILD" "$MIN_MACOS_VERSION" <<'PY'
import plistlib, sys
path, executable, identifier, name, version, build, minimum = sys.argv[1:]
info = dict(CFBundleExecutable=executable, CFBundleIdentifier=identifier,
            CFBundleName=name, CFBundleDisplayName=name, CFBundlePackageType='APPL',
            CFBundleShortVersionString=version, CFBundleVersion=build,
            CFBundleIconFile='AppIcon', LSMinimumSystemVersion=minimum,
            NSPrincipalClass='NSApplication', NSHighResolutionCapable=True,
            NSHumanReadableCopyright='MIT License. Game artwork belongs to its respective owners.')
with open(path, 'wb') as file: plistlib.dump(info, file)
PY
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "$APP_BUNDLE"
