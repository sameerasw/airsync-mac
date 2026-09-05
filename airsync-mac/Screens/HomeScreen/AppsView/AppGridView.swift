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
    @FocusState private var isSearchFocused: Bool
    @State private var launchingPackageName: String? = nil

    var filteredApps: [AndroidApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(appState.androidApps.values)
        } else {
            return appState.androidApps.values.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var sortedAppsList: [AndroidApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return filteredApps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } else {
            let lowerQuery = query.lowercased()
            return filteredApps.sorted { app1, app2 in
                let name1 = app1.name.lowercased()
                let name2 = app2.name.lowercased()
                
                let starts1 = name1.hasPrefix(lowerQuery)
                let starts2 = name2.hasPrefix(lowerQuery)
                
                if starts1 != starts2 {
                    return starts1
                }
                
                return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 16
            let itemWidth: CGFloat = 80
            let columnsCount = max(1, Int((geometry.size.width + spacing) / (itemWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            ZStack(alignment: .bottom) {
                ScrollView {
                    let sorted = sortedAppsList
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(sorted.enumerated()), id: \.element.packageName) { index, app in
                            AppGridItemView(
                                app: app,
                                isHighlighted: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index == 0,
                                isLaunching: launchingPackageName == app.packageName,
                                onLaunch: {
                                    launchApp(app)
                                }
                            )
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 60)
                }
                .whatsNewPopover(item: .appsGrid, arrowEdge: .top)

                // Hint Chip & Floating Searchbar VStack
                VStack(spacing: 8) {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Press ⏎ to launch")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassBoxIfAvailable(radius: 12)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .bottom))
                            ))
                    }

                    // Liquid glass floating searchbar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search Apps", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isSearchFocused)
                            .onSubmit {
                                if let firstApp = sortedAppsList.first {
                                    launchApp(firstApp)
                                }
                            }
                            .onExitCommand {
                                searchText = ""
                            }

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 260)
                    .glassBoxIfAvailable(radius: 20)
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 16)
            }
        }
        .padding(0)
        .onAppear {
            WhatsNewTourManager.shared.evaluateActiveItem()
            isSearchFocused = true
        }
        .onChange(of: appState.selectedTab) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: isSearchFocused) { _, newValue in
            if !newValue {
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
        }
        .sheet(item: Binding(
            get: {
                appState.configuringLaunchPreferenceFor.map { AppConfigureTarget(id: $0) }
            },
            set: { appState.configuringLaunchPreferenceFor = $0?.id }
        )) { target in
            if let app = appState.androidApps[target.id] {
                AppNotificationSettingsView(app: app)
            }
        }
    }

    private func launchApp(_ app: AndroidApp) {
        if let device = appState.device, appState.adbConnected {
            launchingPackageName = app.packageName
            appState.trackAppUse(app)
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: appState.adbPort,
                deviceName: device.name,
                package: app.packageName
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if launchingPackageName == app.packageName {
                    launchingPackageName = nil
                }
            }
        }
    }
}

private struct AppConfigureTarget: Identifiable {
    let id: String
}

// MARK: - App Grid Item
private struct AppGridItemView: View {
    let app: AndroidApp
    let isHighlighted: Bool
    let isLaunching: Bool
    let onLaunch: () -> Void
    @ObservedObject var appState = AppState.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                AppIconButtonView(app: app)
                    .padding(8)
                    .glassBoxIfAvailable(radius: 15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .opacity(isLaunching ? 0.4 : 1.0)

                if isLaunching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .onTapGesture(perform: onLaunch)
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

        Divider()

        Button {
            appState.configuringLaunchPreferenceFor = app.packageName
        } label: {
            let configured = appState.notificationLaunchPreferences[app.packageName] != nil
            Label(
                configured ? "Edit notification click action" : "Set notification click action",
                systemImage: "arrow.up.forward.app"
            )
        }
    }
}
