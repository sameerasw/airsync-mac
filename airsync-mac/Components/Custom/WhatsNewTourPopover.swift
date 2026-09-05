//
//  WhatsNewTourPopover.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-29.
//

import SwiftUI

struct WhatsNewTourPopover: View {
    let item: WhatsNewTourItem
    let onDismiss: () -> Void
    
    @State private var animateSparkles = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.bounce, value: animateSparkles)
                
                Text(L(item.titleKey))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .onAppear {
                animateSparkles = true
            }
            
            Text(L(item.messageKey))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Spacer()
                
                GlassButtonView(
                    label: "",
                    systemImage: "checkmark.circle",
                    iconOnly: true,
                    size: .large,
                    primary: false,
                    action: onDismiss
                )
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
