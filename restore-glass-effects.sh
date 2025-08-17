#!/bin/bash
# Script to restore glass effects when using Xcode 26.0+
# This will uncomment the glass effect lines and comment out the fallback lines

echo "Restoring glass effects for Xcode 26.0+..."

# Restore GlassBoxView.swift
sed -i '' '
    s|// self\.glassEffect|self.glassEffect|g
    s|// self\.background(.clear)|self.background(.clear)|g
    s|//     \.glassEffect|                .glassEffect|g
    s|self\.background(.thinMaterial, in: \.rect(cornerRadius: radius))|// self.background(.thinMaterial, in: .rect(cornerRadius: radius))|g
    s|self\.background(.thinMaterial, in: \.rect(cornerRadius: cornerRadius))|// self.background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))|g
' airsync-mac/Components/Containers/GlassBoxView.swift

# Restore GlassButtonView.swift
sed -i '' '
    s|// self\.buttonStyle(\.glass)|self.buttonStyle(.glass)|g
    s|// self\.buttonStyle(\.glassProminent)|self.buttonStyle(.glassProminent)|g
' airsync-mac/Components/Buttons/GlassButtonView.swift

# Restore SaveAndRestartButton.swift
sed -i '' '
    s|// self\.buttonStyle(\.glass)|self.buttonStyle(.glass)|g
' airsync-mac/Components/Buttons/SaveAndRestartButton.swift

# Restore ScannerView.swift
sed -i '' '
    s|// \.glassEffect|.glassEffect|g
    s|\.background(.thinMaterial, in: \.rect(cornerRadius: 20))|// .background(.thinMaterial, in: .rect(cornerRadius: 20))|g
' airsync-mac/Screens/ScannerView/ScannerView.swift

# Set RuntimeUI to enable glass effects
sed -i '' 's|static let pretendOlderOS = true|static let pretendOlderOS = false|g' airsync-mac/Constants/RuntimeUI.swift

echo "Glass effects restored! Remember to use Xcode 26.0+ for compilation."