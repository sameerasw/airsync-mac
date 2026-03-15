//
//  MenuBarManager.swift
//  AirSync
//
//  Created by Sameera Wijerathna
//

import SwiftUI
import AppKit
internal import Combine

class MenuBarManager: NSObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var appState = AppState.shared
    private var temporaryDragLabel: String?
    
    private let statusButton: MenuBarStatusButton = {
        let view = MenuBarStatusButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        return view
    }()
    
    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        setupBindings()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            statusButton.statusItem = statusItem
            statusButton.clickHandler = { [weak self] in
                self?.togglePopover()
            }
            
            // Add statusButton as a subview of the statusItem's button to handle events
            button.addSubview(statusButton)
            statusButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                statusButton.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                statusButton.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                statusButton.topAnchor.constraint(equalTo: button.topAnchor),
                statusButton.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            
            updateStatusItem()
        }
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenubarView().environmentObject(appState))
        self.popover = popover
    }
    
    private func setupBindings() {
        // Update menu bar when appState changes
        Publishers.Merge5(
            appState.$device.map { _ in () },
            appState.$notifications.map { _ in () },
            appState.$status.map { _ in () },
            appState.$showMenubarText.map { _ in () },
            appState.$showingQuickShareTransfer.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.updateStatusItem()
        }
        .store(in: &cancellables)
        
    }
    
    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        
        // Update icon based on state
        let iconName = appState.device != nil
            ? (appState.notifications.isEmpty ? "iphone.gen3" : "iphone.gen3.radiowaves.left.and.right")
            : "iphone.slash"
        
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AirSync")
        button.imagePosition = .imageLeft
        
        // Update text if enabled
        if let dragLabel = temporaryDragLabel {
            button.title = dragLabel
        } else if appState.showMenubarText, let text = getDeviceStatusText() {
            button.title = text
        } else {
            button.title = ""
        }
    }
    
    func showDragLabel(_ label: String) {
        temporaryDragLabel = label
        updateStatusItem()
    }
    
    func clearDragLabel() {
        temporaryDragLabel = nil
        updateStatusItem()
    }
    
    private func getDeviceStatusText() -> String? {
        guard let device = appState.device else { return nil }
        
        let unreadCount = appState.notifications.count
        let unreadPrefix = unreadCount > 0 ? "\(unreadCount)* • " : ""
        
        if let music = appState.status?.music, music.isPlaying {
            let title = music.title.isEmpty ? "Unknown Title" : music.title
            let artist = music.artist.isEmpty ? "Unknown Artist" : music.artist
            let fullText = unreadPrefix + "\(title) • \(artist)"
            return truncate(text: fullText)
        } else {
            var parts: [String] = []
            if appState.showMenubarDeviceName {
                parts.append(device.name)
            }
            
            if let batteryLevel = appState.status?.battery.level {
                parts.append("\(batteryLevel)%")
            }
            let statusText = parts.isEmpty ? nil : parts.joined(separator: " • ")
            return statusText.map { truncate(text: unreadPrefix + $0) }
        }
    }
    
    private func truncate(text: String) -> String {
        let maxLength = appState.menubarTextMaxLength
        if text.count > maxLength {
            return String(text.prefix(maxLength - 1)) + "…"
        }
        return text
    }
    
    func togglePopover() {
        if popover?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            appState.isMenubarWindowOpen = true
            
            // Monitor clicks outside to close
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.hidePopover()
            }
        }
    }
    
    func hidePopover() {
        popover?.performClose(nil)
        appState.isMenubarWindowOpen = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

class MenuBarStatusButton: NSView {
    var statusItem: NSStatusItem?
    var clickHandler: (() -> Void)?
    var dragEnteredHandler: (() -> Void)?
    var dragExitedHandler: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .string])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragLabel()
        dragEnteredHandler?()
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragLabel()
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        MenuBarManager.shared.clearDragLabel()
        dragExitedHandler?()
    }
    
    private func updateDragLabel() {
        let optionPressed = NSEvent.modifierFlags.contains(.option)
        let label: String
        if optionPressed {
            label = Localizer.shared.text("quickshare.drop.pick_device")
        } else if let deviceName = AppState.shared.device?.name {
            label = String(format: Localizer.shared.text("quickshare.drop.send_to"), deviceName)
        } else {
            label = Localizer.shared.text("quickshare.drop.pick_device")
        }
        MenuBarManager.shared.showDragLabel(label)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MenuBarManager.shared.clearDragLabel()
        let pboard = sender.draggingPasteboard
        
        // Handle file URLs
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            DispatchQueue.main.async {
                let optionPressed = NSEvent.modifierFlags.contains(.option)
                let connectedDeviceName = AppState.shared.device?.name
                let autoTargetName = (!optionPressed) ? connectedDeviceName : nil
                
                QuickShareManager.shared.transferURLs = urls
                QuickShareManager.shared.startDiscovery(autoTargetName: autoTargetName)
                AppState.shared.showingQuickShareTransfer = true
            }
            return true
        }
        
        // Handle strings
        if let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [String], let text = strings.first {
            DispatchQueue.main.async {
                AppState.shared.sendClipboardToAndroid(text: text)
            }
            return true
        }
        
        return false
    }
}
