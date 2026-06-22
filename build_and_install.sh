#!/bin/bash
set -e

echo "Building AirSync..."
# We use the "AirSync" scheme and "Self Compiled" configuration based on your setup.
# The package resolution is handled automatically by xcodebuild when using -scheme.
xcodebuild -project AirSync.xcodeproj -scheme "AirSync" -configuration "Self Compiled" -derivedDataPath ./build

echo "Killing existing AirSync processes..."
pkill -f "AirSync.app/Contents/MacOS/airsync-mac" || true
pkill -x "airsync-mac" || true
pkill -x "AirSync" || true
sleep 1

echo "Removing old AirSync from /Applications..."
rm -rf /Applications/AirSync.app

echo "Copying new AirSync to /Applications..."
cp -R build/Build/Products/Self\ Compiled/AirSync.app /Applications/AirSync.app

echo "Launching new AirSync app..."
open /Applications/AirSync.app

echo "Done!"
