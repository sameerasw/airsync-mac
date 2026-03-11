//
//  DropTargetModifier.swift
//  airsync-mac
//
//  Created by AI Assistant on 2025-09-30.
//

import SwiftUI
import UniformTypeIdentifiers

struct DropTargetModifier: ViewModifier {
    @State private var isTargeted = false
    let appState: AppState

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.plainText, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            .overlay(
                Group {
                    if isTargeted {
                        DropTargetOverlay()
                    }
                }
            )
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard appState.device != nil else {
            // Show notification if no device connected
            appState.postNativeNotification(
                id: "no_device",
                appName: "AirSync",
                title: "No Device Connected",
                body: "Connect an Android device first to send text"
            )
            return
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                    if let text = item as? String ?? (item as? Data).flatMap({ String(data: $0, encoding: .utf8) }) {
                        DispatchQueue.main.async {
                            sendTextToDevice(text)
                        }
                    }
                }
                return
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard let url = (item as? URL) ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) else { return }

                    // Initiate file transfer
                    DispatchQueue.main.async {
                         WebSocketServer.shared.sendFile(url: url)
                    }
                }
                return
            }
        }
    }

    private func sendTextToDevice(_ text: String) {
        appState.sendClipboardToAndroid(text: text)
    }
}

struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                .padding(8)
            
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(4)
        .allowsHitTesting(false)
    }
}

extension View {
    func dropTarget(appState: AppState) -> some View {
        self.modifier(DropTargetModifier(appState: appState))
    }
}
