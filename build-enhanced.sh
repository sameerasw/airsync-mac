#!/bin/bash

set -euo pipefail

SCHEME="AirSync Self Compiled"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-./build}"
RELEASE_DIR="${RELEASE_DIR:-./release}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"

RUN_APP=false
INSTALL_APP=false

for arg in "$@"; do
    case "$arg" in
        --run)
            RUN_APP=true
            ;;
        --install)
            INSTALL_APP=true
            ;;
    esac
done

echo "Building AirSync macOS (${CONFIGURATION})..."

if [ ! -d "AirSync.xcodeproj" ]; then
    echo "AirSync.xcodeproj not found"
    exit 1
fi

mkdir -p "${RELEASE_DIR}"

xcodebuild \
    -project AirSync.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk macosx \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$(find "${DERIVED_DATA_PATH}/Build/Products" -path "*/AirSync.app" -type d | head -1)"
if [ -z "${APP_PATH}" ]; then
    echo "Built app not found"
    exit 1
fi

rm -rf "${RELEASE_DIR}/AirSync.app"
cp -R "${APP_PATH}" "${RELEASE_DIR}/AirSync.app"

echo "Packaged app: ${RELEASE_DIR}/AirSync.app"

if [ "${INSTALL_APP}" = true ]; then
    mkdir -p "${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}/AirSync.app"
    cp -R "${RELEASE_DIR}/AirSync.app" "${INSTALL_DIR}/AirSync.app"
    echo "Installed app: ${INSTALL_DIR}/AirSync.app"
fi

if [ "${RUN_APP}" = true ]; then
    pkill -x AirSync >/dev/null 2>&1 || true
    if [ "${INSTALL_APP}" = true ]; then
        open "${INSTALL_DIR}/AirSync.app"
        echo "Launched ${INSTALL_DIR}/AirSync.app"
    else
        open "${RELEASE_DIR}/AirSync.app"
        echo "Launched ${RELEASE_DIR}/AirSync.app"
    fi
fi
