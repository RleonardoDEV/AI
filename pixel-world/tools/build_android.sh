#!/usr/bin/env bash
# Builds a signed release APK of PIXEL WORLD.
#
# Requirements:
#   - Godot 4.3 on PATH, with the 4.3 export templates installed
#   - Java 17+ and an Android SDK with build-tools (apksigner), configured in
#     Godot's editor settings (export/android/android_sdk_path)
#   - A release keystore. Credentials come from the environment, never the repo:
#       PW_KEYSTORE        path to the .keystore
#       PW_KEYSTORE_ALIAS  key alias
#       PW_KEYSTORE_PASS   store/key password
#
# Usage: tools/build_android.sh [output.apk]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/pixel-world.apk}"
: "${PW_KEYSTORE:?set PW_KEYSTORE}" "${PW_KEYSTORE_ALIAS:?set PW_KEYSTORE_ALIAS}" "${PW_KEYSTORE_PASS:?set PW_KEYSTORE_PASS}"
mkdir -p "$(dirname "$OUT")"
godot --headless --import >/dev/null 2>&1 || true
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PW_KEYSTORE" \
GODOT_ANDROID_KEYSTORE_RELEASE_USER="$PW_KEYSTORE_ALIAS" \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PW_KEYSTORE_PASS" \
	godot --headless --export-release "Android" "$OUT"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
