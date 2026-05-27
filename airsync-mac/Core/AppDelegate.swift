//
//  AppDelegate.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-07.
//
import SwiftUI
import Cocoa
import Foundation


final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?

    // Access the single shared AppDelegate instance
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var menuBarManager: MenuBarManager?

    func applicationWillTerminate() {
        AppState.shared.disconnectDevice()
        if AppState.shared.adbConnected {
            ADBConnector.disconnectADB()
        }
        WebSocketServer.shared.stop()
    }

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Initialize Sentry 
        setupSentry()
        
        // Dock icon visibility is now controlled by AppState.hideDockIcon
        AppState.shared.updateDockIconVisibility()
        
        // Initialize Menu Bar Manager
        menuBarManager = MenuBarManager.shared

        // Initialize Quick Share
        _ = QuickShareManager.shared
        
        // Register Services Provider
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // Register for System Sleep/Wake Notifications
        registerForSleepWakeNotifications()
    }

    private func setupSentry() {
        SentryInitializer.start()
    }

    private func registerForSleepWakeNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            self,
            selector: #selector(handleSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemSleep() {
        print("[AppDelegate] System going to sleep. Cleaning up connections and background tasks.")
        
        // 1. Mark system as sleeping to block automatic background connections/scans
        AppState.shared.isSystemSleeping = true
        
        // 2. Disconnect active device connection cleanly
        AppState.shared.disconnectDevice(isManual: false)
        
        // 3. Stop WebSocket server
        WebSocketServer.shared.stop()
        
        // 4. Stop BLE scanning explicitly
        BLECentralManager.shared.stopScanning()
        
        // 5. Stop UDP Discovery
        UDPDiscoveryManager.shared.stop()
    }

    @objc private func handleSystemWake() {
        print("[AppDelegate] System waking up. Resuming services.")
        
        // 1. Mark system as awake
        AppState.shared.isSystemSleeping = false
        
        // 2. Restart WebSocket server
        startWebSocketServer()
        
        // 3. Restart UDP Discovery
        UDPDiscoveryManager.shared.start()
        
        // 4. If BLE Auto Connect is enabled, start BLE scanning
        if AppState.shared.isBLEAutoConnectEnabled {
            BLECentralManager.shared.isManuallyDisconnected = false
            BLECentralManager.shared.startScanning()
        }
        
        // 5. Auto connect to known/last connected device via Quick Connect
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            QuickConnectManager.shared.wakeUpLastConnectedDevice()
        }
    }

    private func startWebSocketServer() {
        let rawPortInt = AppState.shared.myDevice?.port ?? Int(Defaults.serverPort)
        let chosenPort: UInt16
        if rawPortInt <= 0 || rawPortInt > 65_535 {
            print("[AppDelegate] Invalid configured port \(rawPortInt). Falling back to 8080.")
            chosenPort = UInt16(8080)
        } else {
            chosenPort = UInt16(rawPortInt)
        }
        WebSocketServer.shared.start(port: chosenPort)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !urls.isEmpty {
            QuickShareManager.shared.transferURLs = urls
            QuickShareManager.shared.startDiscovery(autoTargetName: nil)
            AppState.shared.showingQuickShareTransfer = true
        }
    }

    @objc func handleServices(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            QuickShareManager.shared.transferURLs = urls
            QuickShareManager.shared.startDiscovery(autoTargetName: nil)
            AppState.shared.showingQuickShareTransfer = true
        }
    }

    // Configure and retain main window when captured
    func configureMainWindowIfNeeded(_ window: NSWindow) {
        if mainWindow == nil || mainWindow !== window {
            mainWindow = window
            window.delegate = self
        }
        window.isReleasedWhenClosed = false
        window.isReleasedWhenClosed = false
    }




    // Public helper to bring the main window to the current Space and focus it
    func showAndActivateMainWindow() {
        guard let window = mainWindow else { return }

        if !AppState.shared.hideDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
            guard let w = window else { return }
            w.collectionBehavior.insert(.moveToActiveSpace)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Foundation.Notification) {
        if let window = (notification as NSNotification).object as? NSWindow,
           window === mainWindow {
            DispatchQueue.main.async {
                if AppState.shared.hideDockIcon {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func windowDidBecomeMain(_ notification: Foundation.Notification) {
        if let window = (notification as NSNotification).object as? NSWindow,
           window === mainWindow {
            if !AppState.shared.hideDockIcon {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }
}


