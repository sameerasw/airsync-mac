//
//  WindowAccessor.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import SwiftUI
import AppKit

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
                if window.identifier?.rawValue == "main" {
                    AppDelegate.shared?.configureMainWindowIfNeeded(window)
                }
                self.callback(window)

                // Observe onboarding state changes if needed
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
