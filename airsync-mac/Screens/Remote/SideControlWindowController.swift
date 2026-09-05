//
//  SideControlWindowController.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-03.
//

import AppKit
import SwiftUI

class SideControlWindowController {
    var window: NSWindow?
    private var isDismissing = false
    
    func show(parent: NSWindow, isMirroring: Bool) {
        guard !isDismissing else { return }
        
        if window == nil {
            let width: CGFloat = 40
            let height: CGFloat = 140
            
            let parentFrame = parent.frame
            let x = parentFrame.origin.x + parentFrame.size.width + 12
            // Start slightly to the left (tucked behind parent frame)
            let startX = parentFrame.origin.x + parentFrame.size.width - width / 2
            let targetX = parentFrame.origin.x + parentFrame.size.width + 12
            let y = parentFrame.origin.y + parentFrame.size.height - height - 60
            
            let panel = NonFocusableWindow(
                contentRect: NSRect(x: startX, y: y, width: width, height: height),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.alphaValue = 0.0
            
            let hostingView = NSHostingView(rootView: SideControlBar())
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            panel.contentView = hostingView
            
            self.window = panel
            parent.addChildWindow(panel, ordered: .above)
            
            // Slide right and fade in animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(NSRect(x: targetX, y: y, width: width, height: height), display: true)
                panel.animator().alphaValue = 1.0
            })
        } else {
            updatePosition(parent: parent)
        }
    }
    
    func updatePosition(parent: NSWindow) {
        guard let window = window, !isDismissing else { return }
        let parentFrame = parent.frame
        let width = window.frame.size.width
        let height = window.frame.size.height
        let x = parentFrame.origin.x + parentFrame.size.width + 12
        let y = parentFrame.origin.y + parentFrame.size.height - height - 60
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
    
    func hide() {
        guard let panel = window, let parent = panel.parent, !isDismissing else { return }
        isDismissing = true
        
        let parentFrame = parent.frame
        let width = panel.frame.size.width
        let height = panel.frame.size.height
        let targetX = parentFrame.origin.x + parentFrame.size.width - width / 2
        let y = parentFrame.origin.y + parentFrame.size.height - height - 60
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(NSRect(x: targetX, y: y, width: width, height: height), display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            parent.removeChildWindow(panel)
            panel.orderOut(nil)
            if self.window == panel {
                self.window = nil
            }
            self.isDismissing = false
        })
    }
}
