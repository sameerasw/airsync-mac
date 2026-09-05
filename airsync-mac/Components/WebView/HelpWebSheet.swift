//
//  HelpWebSheet.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-02.
//

import SwiftUI

struct HelpWebSheet: View {
    @Binding var isPresented: Bool

    @State private var webURL: URL = URL(string: "https://sameerasw.com/docs/airsync")!
    @State private var currentURL: URL = URL(string: "https://sameerasw.com/docs/airsync")!

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                HStack {
                    GlassButtonView(
                        label: "Mac App feedback",
                        systemImage: "apple.logo",
                        action: {
                            openInBrowser("https://github.com/sameerasw/airsync-mac/issues/new/choose")
                        }
                    )

                    GlassButtonView(
                        label: "Android App feedback",
                        systemImage: "smartphone",
                        action: {
                            openInBrowser("https://github.com/sameerasw/airsync-android/issues/new/choose")
                        }
                    )

                    GlassButtonView(
                        label: "Ask the community",
                        systemImage: "questionmark.message",
                        action: {
                            openInBrowser("https://www.reddit.com/r/AirSync/")
                        }
                    )

                    Spacer()

                    GlassButtonView(
                        label: "Open in browser",
                        systemImage: "globe",
                        action: {
                            openInBrowser(currentURL.absoluteString)
                        }
                    )

                    GlassButtonView(
                        label: "Close",
                        systemImage: "xmark",
                        iconOnly: true,
                        action: {
                            isPresented = false
                        }
                    )
                }
                .padding()

                WebView(url: webURL, currentURL: $currentURL)
                    .frame(minWidth: 700, minHeight: 500)
            }
            .padding(3)
        }
        .frame(width: 850, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)
    }

    private func openInBrowser(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
