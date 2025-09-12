#!/bin/zsh
set -euo pipefail

echo "[SignTools] Starting embedded tools signing…"

# Skip if code signing is not allowed (e.g., on clean CI steps)
if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]]; then
  echo "[SignTools] CODE_SIGNING_ALLOWED != YES; skipping."
  exit 0
fi

# Resolve key build paths
APP_BUNDLE_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
MACOS_DIR="${APP_BUNDLE_PATH}/Contents/MacOS"
SRCROOT_DIR="${SRCROOT}"

# Binaries expected to be copied into Contents/MacOS by your Copy Files phase
TOOLS=("adb" "scrcpy")

# Entitlements for each tool (already in your repo)
ADB_ENTITLEMENTS="${SRCROOT_DIR}/airsync-mac/Binaries/adb_sandbox.entitlements"
SCRCPY_ENTITLEMENTS="${SRCROOT_DIR}/airsync-mac/Binaries/scrcpy_sandbox.entitlements"

# Determine a signing identity. When using Automatic Signing, EXPANDED_CODE_SIGN_IDENTITY is set.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
  echo "[SignTools] No code signing identity found. Ensure the target has a valid signing identity."
  exit 1
fi

function sign_tool() {
  local tool_name="$1"
  local entitlements_path="$2"
  local tool_path="${MACOS_DIR}/${tool_name}"

  if [[ ! -f "${tool_path}" ]]; then
    echo "[SignTools] Skipping ${tool_name}: not found at ${tool_path}"
    return 0
  fi

  if [[ ! -f "${entitlements_path}" ]]; then
    echo "[SignTools] ERROR: Entitlements file missing for ${tool_name}: ${entitlements_path}"
    exit 1
  fi

  echo "[SignTools] Preparing ${tool_name}…"
  chmod +x "${tool_path}"

  echo "[SignTools] Signing ${tool_name} with sandbox entitlements…"
  /usr/bin/codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "${entitlements_path}" \
    --sign "${SIGN_IDENTITY}" \
    "${tool_path}"

  echo "[SignTools] Verifying ${tool_name}…"
  # Avoid --deep here to limit sandbox reads to just the tool
  /usr/bin/codesign --verify --strict --verbose=2 "${tool_path}" || {
    echo "[SignTools] Verification failed for ${tool_name}."
    exit 1
  }

  echo "[SignTools] ${tool_name} signed successfully."
}

# Sign each tool with its corresponding entitlements
sign_tool "adb" "${ADB_ENTITLEMENTS}"
sign_tool "scrcpy" "${SCRCPY_ENTITLEMENTS}"

echo "[SignTools] Embedded tools signing complete."
