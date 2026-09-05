//
//  AppleIntelligenceSettingsView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-06-05.
//

import SwiftUI

struct AppleIntelligenceSettingsView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if #available(macOS 26.0, *) {
                    // Section 1: Disable AI
                    headerSection(title: L("settings.appleIntelligence"), icon: "sparkles")
                    VStack {
                        SettingsToggleView(
                            name: L("settings.notifications.ai.disableAll"),
                            icon: "sparkles.slash",
                            isOn: $appState.disableAllAIFeatures
                        )
                    }
                    .padding()
                    .glassBoxIfAvailable(radius: 18)
                    
                    // Section 2: Notification summaries
                    if !appState.disableAllAIFeatures {
                        headerSection(title: "Notification summaries", icon: "doc.text.magnifyingglass")
                        VStack(spacing: 12) {
                            SettingsToggleView(
                                name: L("settings.notifications.ai.showToolbarButton"),
                                icon: "sparkles",
                                isOn: $appState.showAIToolbarButton
                            )
                            
                            SettingsToggleView(
                                name: L("settings.notifications.ai.includeSilent"),
                                icon: "bell.slash",
                                isOn: $appState.includeSilentInAIOption
                            )
                            
                            SettingsToggleView(
                                name: L("settings.notifications.ai.menubarSummary"),
                                icon: "menubar.arrow.up.rectangle",
                                isOn: $appState.enableMenubarAISummary
                            )
                            
                            SettingsToggleView(
                                name: L("settings.notifications.ai.autoMenubarSummary"),
                                icon: "sparkles.rectangle.stack",
                                isOn: $appState.autoMenubarSummary
                            )
                            .disabled(!appState.enableMenubarAISummary)
                            .opacity(appState.enableMenubarAISummary ? 1.0 : 0.5)
                        }
                        .padding()
                        .glassBoxIfAvailable(radius: 18)
                    }
                } else {
                    // Unavailable view
                    headerSection(title: L("settings.notifications.ai.unavailable.title"), icon: "exclamationmark.triangle")
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        
                        Text(L("settings.notifications.ai.unavailable.title"))
                            .font(.headline)
                        
                        Text(L("settings.notifications.ai.unavailable.body"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .glassBoxIfAvailable(radius: 18)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func headerSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
