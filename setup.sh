#!/bin/bash
# HHRCS — Xcode project setup via xcodegen
# Run this once from the HunterHouseApp directory.

set -e

if ! command -v xcodegen &> /dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

# xcodegen 2.45+ defaults to objectVersion 77 (Xcode 16 format).
# Patch to 56 so the project opens in Xcode 15.4.
sed -i '' 's/objectVersion = 77;/objectVersion = 56;/' HHRCS.xcodeproj/project.pbxproj

echo ""
echo "Done. Open HHRCS.xcodeproj in Xcode."
echo ""
echo "Required Xcode settings after opening:"
echo "  1. Select the HHRCS target → Signing & Capabilities"
echo "  2. Set your Development Team"
echo "  3. Build and run on iOS 17+ device/simulator or macOS 14+"
echo ""
echo "To change the MJPEG stream URL, edit:"
echo "  HHRCS/Camera/MJPEGStreamView.swift  (defaultStreamURL constant)"
