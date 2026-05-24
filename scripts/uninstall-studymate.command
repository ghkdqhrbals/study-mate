#!/bin/bash
set -euo pipefail

APP_NAME="StudyMate"
NEW_BUNDLE_ID="io.github.ghkdqhrbals.StudyMate"
OLD_BUNDLE_ID="com.local.StudyMate"

echo "Uninstalling ${APP_NAME}..."

osascript -e 'tell application "StudyMate" to quit' >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true

rm -rf "/Applications/${APP_NAME}.app"
rm -rf "${HOME}/Applications/${APP_NAME}.app"

for bundle_id in "${NEW_BUNDLE_ID}" "${OLD_BUNDLE_ID}"; do
  defaults delete "${bundle_id}" >/dev/null 2>&1 || true
  rm -f "${HOME}/Library/Preferences/${bundle_id}.plist"
  rm -rf "${HOME}/Library/Application Support/${bundle_id}"
  rm -rf "${HOME}/Library/Caches/${bundle_id}"
  rm -rf "${HOME}/Library/Logs/${bundle_id}"
  rm -rf "${HOME}/Library/Saved Application State/${bundle_id}.savedState"
done

echo ""
echo "StudyMate has been removed."
echo "If the app is still visible in the menu bar, restart your Mac."
read -r -p "Press Return to close this window."
