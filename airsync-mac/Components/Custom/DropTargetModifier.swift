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
    @State private var dragLabel: String = ""
    let appState: AppState

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.plainText, .fileURL], delegate: QuickShareDropDelegate(
                appState: appState,
                isTargeted: $isTargeted,
                dragLabel: $dragLabel
            ))
            .overlay(
                Group {
                    if isTargeted {
                        DropTargetOverlay(label: dragLabel)
                    }
                }
            )
    }
}

struct QuickShareDropDelegate: DropDelegate {
    let appState: AppState
    @Binding var isTargeted: Bool
    @Binding var dragLabel: String
    
    private func updateLabel() {
        let optionPressed = NSEvent.modifierFlags.contains(.option)
        if optionPressed {
            dragLabel = Localizer.shared.text("quickshare.drop.pick_device")
        } else if let deviceName = appState.device?.name {
            dragLabel = String(format: Localizer.shared.text("quickshare.drop.send_to"), deviceName)
        } else {
            dragLabel = Localizer.shared.text("quickshare.drop.pick_device")
        }
    }
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
        updateLabel()
    }
    
    func dropUpdated(info: DropInfo) -> DropOperation? {
        updateLabel()
        return .copy
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        
        let providers = info.itemProviders(for: [.plainText, .fileURL])
        handleDrop(providers: providers)
        return true
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let group = DispatchGroup()
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
                
                QuickShareManager.shared.transferURLs = urls
                QuickShareManager.shared.startDiscovery(autoTargetName: targetName)
                appState.showingQuickShareTransfer = true
            } else if let text = text {
                appState.sendClipboardToAndroid(text: text)
            }
        }
    }
}

struct DropTargetOverlay: View {
    let label: String
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                .padding(8)
            
            VStack(spacing: 16) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text(label)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(4)
        .allowsHitTesting(false)
    }
}

extension View {
    func dropTarget(appState: AppState, autoTargetName: String? = nil) -> some View {
        self.modifier(DropTargetModifier(appState: appState))
    }
}
