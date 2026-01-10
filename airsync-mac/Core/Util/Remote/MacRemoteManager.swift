//
//  MacRemoteManager.swift
//  airsync-mac
//
//  Created by AirSync on 2026-01-10.
//

import Foundation
import Cocoa
import Carbon
import AudioToolbox
internal import Combine

class MacRemoteManager: ObservableObject {
    static let shared = MacRemoteManager()
    
    @Published var lastVolumeLevel: Int = 0
    private var volumeCheckTimer: Timer?
    
    // Key codes
    enum Key: Int {
        case leftArrow = 123
        case rightArrow = 124
        case downArrow = 125
        case upArrow = 126
        case space = 49
        case enter = 36
        case escape = 53
    }
    
    // Media keys (System defined)
    enum MediaKey: Int32 {
        case playPause = 16 // NX_KEYTYPE_PLAY
        case next = 19     // NX_KEYTYPE_NEXT
        case previous = 20 // NX_KEYTYPE_PREVIOUS
        case fast = 17     // NX_KEYTYPE_FAST
        case rewind = 18   // NX_KEYTYPE_REWIND
        case soundUp = 0   // NX_KEYTYPE_SOUND_UP
        case soundDown = 1 // NX_KEYTYPE_SOUND_DOWN
        case mute = 7      // NX_KEYTYPE_MUTE
    }
    
    private init() {
        // Initialize last known volume
        self.lastVolumeLevel = getVolume()
        startVolumeMonitoring()
    }
    
    deinit {
        stopVolumeMonitoring()
    }
    
    // MARK: - Permissions
    
    func isAccessibilityTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Input Simulation
    
    func simulateKeyCode(_ code: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    func simulateText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            // Create a blank event
            if let event = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                var charCode = Array(String(char).utf16)
                event.keyboardSetUnicodeString(stringLength: charCode.count, unicodeString: &charCode)
                event.post(tap: .cghidEventTap)
            }
            
             if let eventUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                 eventUp.post(tap: .cghidEventTap)
             }
        }
    }

    func simulateKey(_ key: Key) {
        simulateKeyCode(key.rawValue)
    }
    
    func simulateMediaKey(_ key: MediaKey) {
        func doKey(down: Bool) {
            let performVal = Int((key.rawValue << 16) | (down ? 0xa00 : 0xb00))
            
            if let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: .init(rawValue: 0xa00),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: performVal,
                data2: -1
            ) {
                event.cgEvent?.post(tap: .cghidEventTap)
            }
        }
        
        doKey(down: true)
        doKey(down: false)
    }
    
    // MARK: - Volume Control
    
    func setVolume(_ percent: Int) {
        let constrained = max(0, min(100, percent))
        let scriptSource = "set volume output volume \(constrained)"
        executeAppleScript(scriptSource)
        
        // Update local state immediately for responsiveness
        self.lastVolumeLevel = constrained
        notifyVolumeChange()
    }
    
    func getVolume() -> Int {
        let scriptSource = "output volume of (get volume settings)"
        if let result = executeAppleScript(scriptSource), let val = Int(result) {
            return val
        }
        return 0
    }
    
    func increaseVolume() {
        // Using media keys gives visual feedback (OSD)
        simulateMediaKey(.soundUp)
        // Update tracking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.lastVolumeLevel = self.getVolume()
            self.notifyVolumeChange()
        }
    }
    
    func decreaseVolume() {
        simulateMediaKey(.soundDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.lastVolumeLevel = self.getVolume()
            self.notifyVolumeChange()
        }
    }
    
    func toggleMute() {
        simulateMediaKey(.mute)
    }
    
    // MARK: - Monitoring & Sync
    
    private func startVolumeMonitoring() {
        volumeCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkVolumeChange()
        }
    }
    
    private func stopVolumeMonitoring() {
        volumeCheckTimer?.invalidate()
        volumeCheckTimer = nil
    }
    
    private func checkVolumeChange() {
        let current = getVolume()
        if current != lastVolumeLevel {
            lastVolumeLevel = current
            notifyVolumeChange()
        }
    }
    
    private func notifyVolumeChange() {
        DispatchQueue.main.async {
            // Send update via WebSocket
            WebSocketServer.shared.sendMacVolumeUpdate(level: self.lastVolumeLevel)
        }
    }
    
    // MARK: - Helpers
    
    @discardableResult
    private func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let output = script.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript error: \(err)")
                return nil
            }
            return output.stringValue
        }
        return nil
    }
}
