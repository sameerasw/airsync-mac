//
//  PlusUnlockedSheet.swift
//  AirSync
//
//  Simple, transparent sheet shown after activating AirSync+.
//

import SwiftUI
import AppKit

struct PlusUnlockedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Match onboarding’s transparent blur backdrop for a nice look
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 14) {
                Text("🎉")
                    .font(.system(size: 50))
                    .padding()

                Text("Thank you for supporting AirSync")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text("AirSync+ features are now available:")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                            featureRow(icon: "macbook.and.iphone", title: "Android Mirroring", description: "Mirror your Android screen and apps to your Mac with full control, wirelessly")
                            featureRow(icon: "music.note", title: "Media Controls", description: "Control music playback and volume directly from your Mac")
                            featureRow(icon: "desktopcomputer", title: "Wireless Desktop Mode", description: "Use the phone in a familiar way, with full desktop controls")
                            featureRow(icon: "phone", title: "Call controls", description: "Accept, decline, or end calls directly from your Mac")
                            featureRow(icon: "app.grid", title: "Custom App Icons", description: "Match your device, Make it personal")
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 250)
                    .cornerRadius(12)
                }

                HStack(spacing: 8) {
                    #if !SELF_COMPILED
                    GlassButtonView(
                        label: "Unregister",
                        systemImage: "xmark.circle",
                        size: .large,
                        action: {
                            AppState.shared.licenseDetails = nil
                            TrialManager.shared.clearTrial()
                            AppState.shared.isPlus = false
                        }
                    )
                    .focusable(false)
                    #endif

                    GlassButtonView(
                        label: "Awesome",
                        systemImage: "arrow.right.circle",
                        size: .large,
                        primary: true,
                        action: {
                            dismiss()
                        }
                    )
                    .focusable(false)
                }

            }
            .frame(maxWidth: 560)
            .padding()
        }
        .frame(minWidth: 640)
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title3)
                Text(description)
            }
            Spacer()
        }
    }
}

#Preview { PlusUnlockedSheet() }
