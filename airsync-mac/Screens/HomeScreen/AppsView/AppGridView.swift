//
//  AppGridView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-07.
//
// Refactored into separate structs to fix compiler type-checking performance

import SwiftUI

struct AppGridView: View {
    @ObservedObject var appState = AppState.shared
    @State private var searchText: String = ""

    var filteredApps: [AndroidApp] {
        if searchText.isEmpty {
            return Array(appState.androidApps.values)
        } else {
            return appState.androidApps.values.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.packageName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 16
            let itemWidth: CGFloat = 80
            let columnsCount = max(1, Int((geometry.size.width + spacing) / (itemWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredApps.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }), id: \.packageName) { app in
                        AppGridItemView(app: app)
                    }
                }
                .padding(12)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Apps")
        .padding(0)
    }
}

// MARK: - App Grid Item
private struct AppGridItemView: View {
    let app: AndroidApp
    @ObservedObject var appState = AppState.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppIconButtonView(app: app)
                .padding(8)
                .glassBoxIfAvailable(radius: 15)
                .onTapGesture(perform: handleTap)
                .contextMenu {
                    AppContextMenuContent(app: app)
                }
                .onDrag(createDragProvider)

            // Notification mute indicator
            if !app.listening {
                Image(systemName: "bell.slash")
                    .resizable()
                    .frame(width: 10, height: 10)
                    .offset(x: -8, y: 8)
            }
        }
    }

    private func handleTap() {
        if let device = appState.device, appState.adbConnected {
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: appState.adbPort,
                deviceName: device.name,
                package: app.packageName
            )
        }
    }

    private func createDragProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        do {
            let jsonData = try JSONEncoder().encode(app)
            provider.registerDataRepresentation(
                forTypeIdentifier: "com.sameerasw.airsync.app",
                visibility: .all
            ) { completion in
                completion(jsonData, nil)
                return nil
            }

            provider.registerDataRepresentation(
                forTypeIdentifier: "public.json",
                visibility: .all
            ) { completion in
                completion(jsonData, nil)
                return nil
            }

            print("[drag] Registered drag provider for app: \(app.name), size: \(jsonData.count) bytes")
        } catch {
            print("[drag] Error encoding app for drag: \(error)")
        }

        return provider
    }
}

// MARK: - App Icon View
private struct AppIconButtonView: View {
    let app: AndroidApp

    var body: some View {
        VStack(spacing: 8) {
            if let iconPath = app.iconUrl,
               let image = Image(filePath: iconPath) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
            } else {
                Image(systemName: "app.badge")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.gray)
            }

            Text(app.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Context Menu
private struct AppContextMenuContent: View {
    let app: AndroidApp
    @ObservedObject var appState = AppState.shared

    var isPinned: Bool {
        appState.pinnedApps.contains(where: { $0.packageName == app.packageName })
    }

    var body: some View {
        // Pin/Unpin option (only for Plus members)
//        if appState.isPlus {
//            if !isPinned {
//                Button {
//                    _ = appState.addPinnedApp(app)
//                } label: {
//                    Label("Pin to Dock", systemImage: "pin")
//                }
//            } else {
//                Button {
//                    appState.removePinnedApp(app.packageName)
//                } label: {
//                    Label("Unpin from Dock", systemImage: "pin.slash")
//                }
//            }
//
//            Divider()
//        }

        // Notification toggle
        Button {
            WebSocketServer.shared
                .toggleNotification(
                    for: app.packageName,
                    to: !app.listening
                )
        } label: {
            Label(
                app.listening ? "Mute app" : "Unmute app",
                systemImage: app.listening ? "bell.slash" : "bell.and.waves.left.and.right"
            )
        }
    }
}
