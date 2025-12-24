//
//  airsync_macApp.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI
import UserNotifications
import AppKit
import Sparkle

@main
struct airsync_macApp: App {
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    let notificationDelegate = NotificationDelegate()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @AppStorage("hasPairedDeviceOnce") private var hasPairedDeviceOnce: Bool = false
    private let updaterController: SPUStandardUpdaterController

    // Initialize NowPlayingViewModel to start sending media info to Android
    @StateObject private var macInfoSyncManager = MacInfoSyncManager()

    init() {

        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.checkForUpdatesInBackground()

        // Register base default category with generic View action; dynamic per-notification categories added later
        let viewAction = UNNotificationAction(identifier: "VIEW_ACTION", title: "View", options: [])
        let defaultCategory = UNNotificationCategory(identifier: "DEFAULT_CATEGORY", actions: [viewAction], intentIdentifiers: [], options: [])
        center.getNotificationCategories { existing in
            center.setNotificationCategories(existing.union([defaultCategory]))
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[main-app] Notification permission error: \(error)")
            } else {
                print("[main-app] Notification permission granted: \(granted)")
            }
        }

        let rawPortInt = AppState.shared.myDevice?.port ?? Int(Defaults.serverPort)
        let chosenPort: UInt16
        if rawPortInt <= 0 || rawPortInt > 65_535 {
            print("[main-app] Invalid configured port \(rawPortInt). Falling back to 8080.")
            chosenPort = UInt16(8080)
        }
        else {
            chosenPort = UInt16(rawPortInt)
        }
        WebSocketServer.shared.start(port: UInt16(chosenPort))

        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            AppState.shared.syncWithSystemNotifications()
        }

        loadCachedIcons()
        loadCachedWallpapers()

        // Load saved app icon preference and revert if needed based on license status
        let appIconManager = AppIconManager()
        appIconManager.loadCurrentIcon()

        // Set up listener for license changes to revert icon if needed
        // This will be called when license status changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LicenseStatusChanged"),
            object: nil,
            queue: .main
        ) { _ in
            appIconManager.revertToDefaultIfNeeded()
        }

        // Initialize trial manager early so entitlement state is up-to-date on launch.
        _ = TrialManager.shared

    }

    var body: some Scene {
        MenuBarExtra {
            MenubarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("AirSync", id: "main") {
            if #available(macOS 15.0, *) {
                HomeView()
                    .containerBackground(.ultraThinMaterial, for: .window)
                    .applyMainWindowSetup(appDelegate: appDelegate, appState: appState)
                    .dropTarget(appState: appState)
            } else {
                HomeView()
                    .applyMainWindowSetup(appDelegate: appDelegate, appState: appState)
                    .dropTarget(appState: appState)
            }
        }
        .onChange(of: appState.activeCall) { oldValue, newValue in
            if newValue != nil {
                openWindow(id: "callWindow")
            } else {
                dismissWindow(id: "callWindow")
            }
        }

        // Secondary Tool Window for Calls
        Window("Call", id: "callWindow") {
            if let activeCall = appState.activeCall {
                if #available(macOS 15.0, *) {
                    CallWindowView(callEvent: activeCall)
                        .environmentObject(appState)
                        .containerBackground(.ultraThinMaterial, for: .window)
                } else {
                    CallWindowView(callEvent: activeCall)
                        .environmentObject(appState)
                }
            }
        }
        .defaultPosition(.topTrailing)
        .defaultSize(width: 320, height: 480)
        .windowStyle(.hiddenTitleBar)

    .commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updaterController.updater)
        }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) {
                Button(action: {
                    if let url = URL(string: "https://airsync.notion.site") {
                        NSWorkspace.shared.open(url)
                    }
                }, label: {
                    Text("Help")
                })
                .keyboardShortcut("/")
            }
            // Mirror menu: launch full device mirror or specific apps via scrcpy
            CommandMenu("Mirror") {
                // Primary full-device mirror option
                Button("Android Mirror") {
                    if let device = appState.device, appState.adbConnected {
                        ADBConnector.startScrcpy(
                            ip: device.ipAddress,
                            port: UInt16(appState.adbPort),
                            deviceName: device.name,
                            package: nil
                        )
                    }
                }
                .disabled(!(appState.device != nil && appState.adbConnected))

                // Only show app list if ADB is connected
                if appState.adbConnected, let _ = appState.device {
                    Divider()
                    // Sorted list of apps by display name
                    ForEach(Array(appState.androidApps.values).sorted { $0.name.lowercased() < $1.name.lowercased() }, id: \.packageName) { app in
                        Button(app.name) {
                            if let device = appState.device {
                                ADBConnector.startScrcpy(
                                    ip: device.ipAddress,
                                    port: UInt16(appState.adbPort),
                                    deviceName: device.name,
                                    package: app.packageName
                                )
                            }
                        }
                    }
                }
            }
        }

    }

}

extension View {
    func applyMainWindowSetup(appDelegate: AppDelegate, appState: AppState) -> some View {
        self.background(WindowAccessor(callback: { window in
            window.identifier = NSUserInterfaceItemIdentifier("main")
            appDelegate.mainWindow = window
            window.collectionBehavior.insert(.moveToActiveSpace)
            // Make window transparent during onboarding
            if appState.isOnboardingActive {
                window.alphaValue = 0.0
                window.isOpaque = false
            } else {
                window.alphaValue = 1.0
                window.isOpaque = true
            }
        }, onOnboardingChange: { isActive in
            guard let window = appDelegate.mainWindow else { return }
            // Animate the transition
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                if isActive {
                    window.animator().alphaValue = 0.0
                    window.isOpaque = false
                } else {
                    window.animator().alphaValue = 1.0
                    window.isOpaque = true
                }
            }
        }))
    }
}
