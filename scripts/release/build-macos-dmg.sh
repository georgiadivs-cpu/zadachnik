#!/usr/bin/env bash
set -euo pipefail

# Собирает ad-hoc подписанный DMG для распространения macOS вне App Store.
# Notarization недоступна без платного Apple Developer Program.
#
# Запуск из корня репозитория:
#   ./scripts/release/build-macos-dmg.sh
#
# Результат: dist/macos/zadachnik-<version>.dmg

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLIENT="$ROOT/apps/client"
APP="$CLIENT/build/macos/Build/Products/Release/zadachnik_client.app"
DIST="$ROOT/dist/macos"
VERSION="$(awk '/^version:/ {print $2}' "$CLIENT/pubspec.yaml" | cut -d+ -f1)"
DMG="$DIST/zadachnik-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
  echo "Сначала соберите приложение: (cd apps/client && flutter build macos --release)" >&2
  exit 1
fi

mkdir -p "$DIST"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$DMG"
hdiutil create \
  -volname "Ежедневник" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "DMG: $DMG"
echo
echo "Приложение подписано ad-hoc. При первом запуске на другом Mac:"
echo "  1. Перетащите приложение в /Applications."
echo "  2. Выполните: xattr -dr com.apple.quarantine '/Applications/zadachnik_client.app'"
echo "  3. Или откройте через правый клик → «Открыть»."
echo
echo "Notarization и запуск без предупреждений требуют платного Apple Developer Program."
