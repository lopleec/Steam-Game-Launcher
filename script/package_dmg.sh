#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_config.sh"
"$ROOT_DIR/script/build_app.sh" release universal
STAGE="$(mktemp -d "$ROOT_DIR/dist/dmg-stage.XXXXXX")"
ditto "$ROOT_DIR/dist/$APP_DISPLAY_NAME.app" "$STAGE/$APP_DISPLAY_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT_DIR/LICENSE" "$STAGE/LICENSE.txt"
DMG="$ROOT_DIR/dist/Steam-Game-Launcher-$APP_VERSION-universal.dmg"
hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
# Leave no second launchable app for Launch Services to confuse with dist/.
mv "$STAGE/$APP_DISPLAY_NAME.app" "$STAGE/AppBundle.archive"
(cd "$ROOT_DIR/dist" && shasum -a 256 "${DMG##*/}" > "${DMG##*/}.sha256")
echo "$DMG"
