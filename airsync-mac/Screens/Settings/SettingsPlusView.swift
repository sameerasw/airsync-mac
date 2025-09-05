//
//  SettingsPlusView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-04.
//

import SwiftUI

/// Simplified AirSync+ settings while StoreKit / Play Billing is pending.
/// Provides a session-only toggle that does NOT persist or validate a license.
struct SettingsPlusView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("AirSync+ (temporary toggle)", systemImage: "plus.app")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.isPlus },
                    set: { appState.setPlusTemporarily($0) }
                ))
                .toggleStyle(.switch)
                .help("Session-only. Will reset next launch.")
            }

            DisclosureGroup(isExpanded: $showInfo) {
                Text(L("plus.why"))
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            } label: {
                Text("Why AirSync+?")
                    .font(.subheadline)
                    .bold()
            }
        }
    }
}

#Preview { SettingsPlusView() }
