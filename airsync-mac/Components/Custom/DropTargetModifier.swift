//
//  DropTargetModifier.swift
//  airsync-mac
//
//  Created by AI Assistant on 2025-09-30.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import AppKit

struct DropTargetModifier: ViewModifier {
    @State private var isTargeted = false
    let appState: AppState
    var autoTargetName: String? = nil

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

        let group = DispatchGroup()
        // Collect URLs in a thread-safe way
        var urls: [URL] = []
        let urlLock = NSLock()
        var text: String?
        let textLock = NSLock()

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        urlLock.lock()
                        urls.append(url)
                        urlLock.unlock()
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                    if let s = item as? String ?? (item as? Data).flatMap({ String(data: $0, encoding: .utf8) }) {
                        textLock.lock()
                        text = s
                        textLock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                let optionPressed = NSEvent.modifierFlags.contains(.option)
                let connectedDeviceName = appState.device?.name
                let targetName = (!optionPressed) ? connectedDeviceName : nil
                
                QuickShareManager.shared.startDiscovery(autoTargetName: targetName)
                QuickShareManager.shared.transferURLs = urls
                appState.showingQuickShareTransfer = true
            } else if let text = text {
                sendTextToDevice(text)
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
    func dropTarget(appState: AppState, autoTargetName: String? = nil) -> some View {
        self.modifier(DropTargetModifier(appState: appState, autoTargetName: autoTargetName))
    }
}
