//
//  QuitHoldManager.swift
//  AirSync
//

import AppKit

enum QuitHoldManager {
    private static let holdDuration: TimeInterval = 0.8
    private static let dismissDelay: TimeInterval = 1.5
    private static let fadeDuration: TimeInterval = 0.4
    private static let qKeyCode: UInt16 = 12

    private static var keyMonitor: Any?
    private static var isHolding = false
    private static var quitTimer: Timer?
    private static var dismissTimer: Timer?
    private static var overlayPanel: QuitHoldPanel?

    static func registerIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
        }
    }

    private static func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            guard event.keyCode == qKeyCode, event.modifierFlags.contains(.command) else { return event }
            if !event.isARepeat {
                startHold()
            }
            return nil

        case .keyUp:
            guard event.keyCode == qKeyCode else { return event }
            if isHolding {
                cancelHold()
                return nil
            }
            return event

        case .flagsChanged:
            if isHolding && !event.modifierFlags.contains(.command) {
                cancelHold()
            }
            return event

        default:
            return event
        }
    }

    private static func startHold() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard !isHolding else { return }
        isHolding = true

        overlayPanel?.orderOut(nil)

        let panel = QuitHoldPanel(holdDuration: holdDuration)
        panel.orderFrontRegardless()
        overlayPanel = panel

        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { _ in
            NSApp.terminate(nil)
        }
    }

    private static func cancelHold() {
        isHolding = false
        quitTimer?.invalidate()
        quitTimer = nil
        overlayPanel?.progressModel.isCancelled = true

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissDelay, repeats: false) { _ in
            fadeOutAndDismiss()
        }
    }

    private static func fadeOutAndDismiss() {
        guard let panel = overlayPanel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            if overlayPanel === panel {
                overlayPanel = nil
            }
        })
    }
}
