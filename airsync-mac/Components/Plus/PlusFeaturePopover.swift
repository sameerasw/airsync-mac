//
//  PlusFeaturePopover.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-31.
//

import SwiftUI

struct PlusFeaturePopover: View {
    var message: String = "Available with AirSync+"
    @StateObject private var trialManager = TrialManager.shared
    @ObservedObject var appState = AppState.shared
    @State private var showTrialSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                GlassButtonView(label: "Get +", systemImage: "link", primary: true, action: {
                    if let url = URL(string: "https://store.sameerasw.com") {
                        NSWorkspace.shared.open(url)
                    }
                })

                if appState.licenseDetails == nil && !trialManager.isTrialActive {
                    GlassButtonView(label: "Try for free", systemImage: "play.circle", action: {
                        trialManager.clearError()
                        showTrialSheet = true
                    })
                    .disabled(trialManager.isPerformingRequest || !trialManager.hasSecretConfigured)
                }
            }
        }
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $showTrialSheet) {
            TrialActivationSheet(
                manager: trialManager,
                onActivated: {
                    showTrialSheet = false
                }
            )
        }
    }
}
