//
//  PlusFeaturesView.swift
//  AirSync
//
//  Created by AI Assistant on 2025-09-04.
//

import SwiftUI

struct PlusFeaturesView: View {
    let onNext: () -> Void

    @ObservedObject var appState = AppState.shared

    var body: some View {
        VStack(spacing: 15) {
            Text("AirSync+, to sync even more!")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding()

            Text("Getting AirSync+ supports the development and unlocks more features for you. But, AirSync's core features will always remain free. Appreciate your support. (っ◕‿◕)っ")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

                List{
                    featureRow(icon: "macbook.and.iphone", title: "Android Mirroring", description: "Mirror your Android screen and apps to your Mac with full control, wirelessly")
                    featureRow(icon: "music.note", title: "Media Controls", description: "Control music playback and volume directly from your Mac")
                    featureRow(icon: "desktopcomputer", title: "Wireless Desktop Mode", description: "Use the phone in a familiar way, with full desktop controls")
                    featureRow(icon: "phone", title: "Control calls", description: "Accept, decline, or end phone calls from your Mac (ADB)")
                    featureRow(icon: "app.grid", title: "Custom App Icons", description: "Match your device, Make it personal")
                    featureRow(icon: "bell.badge", title: "Advanced Notifications", description: "Enhanced notification management and customization", soon: true)
                    featureRow(icon: "battery.25percent", title: "Low Battery Alerts", description: "Get notified when your Android device needs charging", soon: true)
                    featureRow(icon: "widget.small.badge.plus", title: "Widgets", description: "Synced widgets with device status and more", soon: true)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 250)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)

            HStack(spacing: 16) {
                GlassButtonView(
                    label: appState.isPlus ? "Thank you" : "Get AirSync+",
                    systemImage: "plus.diamond",
                    size: .large,
                    fixedIconSize: 16,
                    action: {
                        if let url = URL(string: "https://store.sameerasw.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                .disabled(appState.isPlus)
                .transition(.identity)

                GlassButtonView(
                    label: "Let's begin syncing",
                    systemImage: "arrow.right.circle",
                    size: .large,
                    primary: true,
                    fixedIconSize: 16,
                    action: onNext
                )
                .transition(.identity)
            }
        }
    }

    @ViewBuilder
     func featureRow(icon: String, title: String, description: String, soon: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // soon badge
            if soon {
                VStack {
                    Spacer()
                    Text("Soon")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.3))
                        .cornerRadius(8)
                }
            }
        }
        .padding(2)
    }
}
