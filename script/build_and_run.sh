#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_config.sh"
MODE="${1:-run}"
case "$MODE" in --build-only|run|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry) ;; *) echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
if [[ "$MODE" != --build-only ]]; then pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true; fi
"$ROOT_DIR/script/build_app.sh" debug native
APP_BUNDLE="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
case "$MODE" in
    --build-only) ;;
    run) open -n "$APP_BUNDLE" ;;
    --verify|verify)
        open -n "$APP_BUNDLE"
        sleep 2
        pgrep -x "$APP_EXECUTABLE" >/dev/null
        echo "Build and launch verified: $APP_BUNDLE" ;;
    --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" ;;
    --logs|logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE\"" ;;
    --telemetry|telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
esac
