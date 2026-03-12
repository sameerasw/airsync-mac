//
//  ExpandableLicenseSection.swift
//  airsync-mac
//
//  Created by AI Assistant on 2026-03-12.
//

import SwiftUI

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
