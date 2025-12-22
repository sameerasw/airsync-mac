//
//  AboutView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-31.
//

import SwiftUI

struct AboutView: View {
    let onClose: () -> Void

    var body: some View {

        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("About AirSync")
                            .font(.title2)
                            .bold()

                        Text("v\(Bundle.main.appVersion)")

                        // Profile image
                        Image("avatar")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .padding()

                        Text("Developed by Sameera Wijerathna")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("With ❤️ from 🇱🇰")
                            .font(.callout)
                            .multilineTextAlignment(.center)

                        Text("AirSync helps you achieving Apple continuity features of mac with Android. This is the macOS client which handles the server. It will utilize a websocket for connectivity between the Android device(s) in the local network.")
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal)

                        HStack{

                            GlassButtonView(
                                label: "How to use?",
                                systemImage: "questionmark.circle",
                                primary: true,
                                action: {
                                    if let url = URL(string: "https://airsync.notion.site") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            )

                            GlassButtonView(
                                label: "Website",
                                systemImage: "globe",
                                action: {
                                    if let url = URL(string: "https://github.com/sameerasw/airsync-mac") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            )

                            GlassButtonView(
                                label: "GitHub",
                                systemImage: "folder",
                                action: {
                                    if let url = URL(string: "https://github.com/sameerasw/airsync-mac") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            )

                            GlassButtonView(
                                label: "Get for Android",
                                systemImage: "iphone.gen3",
                                action: {
                                    if let url = URL(string: "https://play.google.com/store/apps/details?id=com.sameerasw.airsync") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            )
                        }

                        Divider()

                        LicenseView()

                    }
                    .padding()
                }

                Divider()

                HStack {
                    Spacer()

                    GlassButtonView(
                        label: "Reset Onboarding",
                        systemImage: "repeat",
                        action: {
                            if UserDefaults.standard.hasPairedDeviceOnce == true {
                                UserDefaults.standard.hasPairedDeviceOnce = false
                                UserDefaults.standard.resetOnboarding()
                            }
                        }
                    )

                    GlassButtonView(
                        label: "My Website",
                        systemImage: "link",
                        action: {
                            if let url = URL(string: "https://sameerasw.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )

                    GlassButtonView(
                        label: "OK",
                        action: {
                            onClose()
                        }
                    )
                    .keyboardShortcut(.defaultAction)
                }
                .padding([.horizontal, .bottom])
            }

        }
        .frame(width: 600, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)

    }
}

struct ExpandableLicenseSection: View {
    let title: String
    let content: String
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(content)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        } label: {
            Text(title)
                .font(.subheadline)
                .bold()
        }
        .focusEffectDisabled()
    }
}
