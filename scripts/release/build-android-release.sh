#!/usr/bin/env bash
set -euo pipefail

# Собирает подписанный release APK и кладёт его в dist/android.
# Keystore и пароли должны быть в apps/client/android/key.properties.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLIENT="$ROOT/apps/client"
VERSION="$(awk '/^version:/ {print $2}' "$CLIENT/pubspec.yaml" | cut -d+ -f1)"
DIST="$ROOT/dist/android"
APK="$CLIENT/build/app/outputs/flutter-apk/app-release.apk"

if [[ ! -f "$CLIENT/android/key.properties" ]]; then
  echo "Нет apps/client/android/key.properties. Настройте release keystore." >&2
  exit 1
fi

cd "$CLIENT"
flutter build apk --release
mkdir -p "$DIST"
cp "$APK" "$DIST/zadachnik-$VERSION.apk"

BT="$(find "$HOME/Library/Android/sdk/build-tools" -maxdepth 1 -type d | sort -V | tail -1)"
if [[ -x "$BT/apksigner" ]]; then
  "$BT/apksigner" verify --verbose "$DIST/zadachnik-$VERSION.apk" | head -8
fi
if [[ -x "$BT/aapt" ]]; then
  "$BT/aapt" dump badging "$DIST/zadachnik-$VERSION.apk" |
    grep -E "package:|application-label:|sdkVersion|targetSdkVersion" | head -4
fi

if command -v shasum >/dev/null 2>&1; then
  (cd "$DIST" && shasum -a 256 "zadachnik-$VERSION.apk" > "zadachnik-$VERSION.apk.sha256")
fi
echo "APK: $DIST/zadachnik-$VERSION.apk"
