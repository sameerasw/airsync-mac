//
//  QuitHoldPanel.swift
//  AirSync
//

import AppKit
import SwiftUI

class QuitHoldPanel: NSPanel {
    let progressModel = QuitHoldProgressModel()

    init(holdDuration: TimeInterval) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: QuitHoldOverlayView(holdDuration: holdDuration, model: progressModel))
        hostingView.frame = self.contentView?.bounds ?? .zero
        self.contentView = hostingView

        if let screenFrame = NSScreen.main?.frame {
            let size = self.frame.size
            let origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2
            )
            self.setFrameOrigin(origin)
        }
    }

    override var canBecomeKey: Bool { false }
}
