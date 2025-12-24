//
//  WelcomeView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-02.
//

import SwiftUI

struct WelcomeView: View {
    let onNext: () -> Void

    // Animation states
    @State private var showCore: Bool = false 
    @State private var showDetails: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                AnimatedAppIconCarousel(iconSize: 140, cornerRadius: 24)

                Text(UserDefaults.standard.isReturningUser ? "Welcome Back to AirSync!" : "AirSync")
                    .font(.system(size: UserDefaults.standard.isReturningUser ? 30 : 50, weight: .bold, design: .rounded))
                .tracking(0.5)
                .multilineTextAlignment(.center)

                if showDetails {
                    Text("The forbidden continuity for your mac and Android. (っ◕‿◕)っ")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }
            .padding(.top, 8)
            .opacity(showCore ? 1 : 0)
            .scaleEffect(showCore ? 1.0 : 0.5)
            .animation(.spring(duration: 1.0, bounce: 0.5), value: showCore)

            if showDetails {
                VStack(spacing: 22) {
                    HStack {
                        GlassButtonView(
                            label: "How to use?",
                            systemImage: "questionmark.circle",
                            size: .extraLarge,
                            action: {
                                if let url = URL(string: "https://airsync.notion.site") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                        .transition(.identity)

                        GlassButtonView(
                            label: "Let's Start!",
                            systemImage: "arrow.right.circle",
                            size: .extraLarge,
                            primary: true,
                            action: onNext
                        )
                        .transition(.identity)
                    }

                    Text("v\(Bundle.main.appVersion)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)

                    GlassButtonView(
                        label: "What's new?",
                        image: "sparkles.2",
                        action: {
                            if let url = URL(string: "https://github.com/sameerasw/airsync-mac/releases/latest") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )


                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)).animation(.easeOut(duration: 1.5)),
                        removal: .opacity.animation(.easeIn(duration: 1.0))
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .onAppear {
            showCore = true

            let delay = 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation {
                    showDetails = true
                }
            }
        }
    }
}

#Preview {
    WelcomeView(onNext: {})
}
