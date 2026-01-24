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

    func applicationWillTerminate() {
        AppState.shared.disconnectDevice()
        ADBConnector.disconnectADB()
        WebSocketServer.shared.stop()
    }

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Dock icon visibility is now controlled by AppState.hideDockIcon
        AppState.shared.updateDockIconVisibility()
        
        // Register Services Provider
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("[AppDelegate] Opening file: \(url.path)")
            WebSocketServer.shared.sendFile(url: url)
        }
    }

    @objc func handleServices(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                print("[AppDelegate] Services menu received file: \(url.path)")
                WebSocketServer.shared.sendFile(url: url)
            }
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


// Helper to grab NSWindow from SwiftUI:
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    let onOnboardingChange: ((Bool) -> Void)?

    init(callback: @escaping (NSWindow) -> Void, onOnboardingChange: ((Bool) -> Void)? = nil) {
        self.callback = callback
        self.onOnboardingChange = onOnboardingChange
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                AppDelegate.shared?.configureMainWindowIfNeeded(window)
                self.callback(window)

                // Observe onboarding state changes
                if let onOnboardingChange = self.onOnboardingChange {
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("OnboardingStateChanged"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let isActive = notification.userInfo?["isActive"] as? Bool {
                            onOnboardingChange(isActive)
                        }
                    }
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
