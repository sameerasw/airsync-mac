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
    var copyable: Bool = false
    @State private var showCopied: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ZStack(alignment: .topTrailing) {
                Text(content)
                    .font(copyable ? .system(.footnote, design: .monospaced) : .footnote)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture {
                        if copyable {
                            copyToClipboard(content)
                        }
                    }
                
                if showCopied {
                    Text("Copied!")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(8)
                        .transition(.opacity)
                }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .bold()
                
                if copyable {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .focusEffectDisabled()
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}
