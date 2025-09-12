BIN_DIR="${PROJECT_DIR}/airsync-mac/Binaries"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
ENTITLEMENTS="${PROJECT_DIR}/AirSync.entitlements"

for BIN in "$BIN_DIR/adb" "$BIN_DIR/scrcpy"; do
  echo "Pre-signing $BIN"
  codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$BIN"
done
