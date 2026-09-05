//
//  NonFocusableWindow.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-03.
//

import AppKit

class NonFocusableWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
