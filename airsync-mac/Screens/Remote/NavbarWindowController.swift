//
//  NavbarWindowController.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-03.
//

import AppKit
import SwiftUI

class NavbarWindowController {
    var window: NSWindow?
    private var isDismissing = false
    
    func show(parent: NSWindow, isMirroring: Bool) {
        guard !isDismissing else { return }
        
        if window == nil {
            let width: CGFloat = 140
            let height: CGFloat = 40
            
            let parentFrame = parent.frame
            let x = parentFrame.origin.x + (parentFrame.size.width - width) / 2
            // Start slightly higher (tucked right below parent frame)
            let startY = parentFrame.origin.y - height / 2
            let endY = parentFrame.origin.y - height - 12
            
            let panel = NonFocusableWindow(
                contentRect: NSRect(x: x, y: startY, width: width, height: height),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.alphaValue = 0.0
            
            let hostingView = NSHostingView(rootView: FloatingNavbar())
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            panel.contentView = hostingView
            
            self.window = panel
            parent.addChildWindow(panel, ordered: .above)
            
            // Slide down animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(NSRect(x: x, y: endY, width: width, height: height), display: true)
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
        let x = parentFrame.origin.x + (parentFrame.size.width - width) / 2
        let y = parentFrame.origin.y - height - 12
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
    
    func hide() {
        guard let panel = window, let parent = panel.parent, !isDismissing else { return }
        isDismissing = true
        
        let parentFrame = parent.frame
        let width = panel.frame.size.width
        let height = panel.frame.size.height
        let x = parentFrame.origin.x + (parentFrame.size.width - width) / 2
        let targetY = parentFrame.origin.y - height / 2
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(NSRect(x: x, y: targetY, width: width, height: height), display: true)
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
