//
//  MenuBarManager.swift
//  AirSync
//
//  Created by Sameera Wijerathna
//

import SwiftUI
import AppKit
import Combine

class MenuBarManager: NSObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var menubarPanel: MenubarPanel?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var appState = AppState.shared
    private var temporaryDragLabel: String?
    private var hostingView: ClickThroughHostingView?
    
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
            
            // Set up ClickThroughHostingView for SwiftUI custom status bar rendering
            let hostedView = MenubarStatusView()
            let hosting = ClickThroughHostingView(rootView: hostedView)
            button.addSubview(hosting)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            self.hostingView = hosting
            
            // Make sure the native button has no title/image overlay
            button.image = nil
            button.title = ""
            
            updateStatusItem()
        }
    }
    
    private func setupPopover() {
        // Initialized on first show to ensure proper sizing
    }
    
    private func setupBindings() {
        // Update menu bar when appState changes
        let group1: [AnyPublisher<Void, Never>] = [
            appState.$device.map { _ in () }.eraseToAnyPublisher(),
            appState.$notifications.map { _ in () }.eraseToAnyPublisher(),
            appState.$status.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarText.map { _ in () }.eraseToAnyPublisher(),
            appState.$showingQuickShareTransfer.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarIcon.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarCallDetails.map { _ in () }.eraseToAnyPublisher(),
            appState.$activeCall.map { _ in () }.eraseToAnyPublisher(),
            appState.$activeCallDurationSec.map { _ in () }.eraseToAnyPublisher()
        ]
        
        let group2: [AnyPublisher<Void, Never>] = [
            appState.$menubarBatteryStyle.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarMusicIcon.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarAlbumArt.map { _ in () }.eraseToAnyPublisher(),
            appState.$menubarUnreadBadgeStyle.map { _ in () }.eraseToAnyPublisher(),
            appState.$menubarUnreadBadgeColor.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarDeviceName.map { _ in () }.eraseToAnyPublisher(),
            appState.$menubarTextMaxLength.map { _ in () }.eraseToAnyPublisher(),
            appState.$menubarFontSize.map { _ in () }.eraseToAnyPublisher()
        ]
        
        let group3: [AnyPublisher<Void, Never>] = [
            appState.$temporaryDragLabel.map { _ in () }.eraseToAnyPublisher(),
            appState.$showMenubarPillStroke.map { _ in () }.eraseToAnyPublisher(),
            appState.$menubarNotificationStyle.map { _ in () }.eraseToAnyPublisher(),
            BLECentralManager.shared.$connectionStatus.map { _ in () }.eraseToAnyPublisher(),
            BLECentralManager.shared.$connectedDeviceName.map { _ in () }.eraseToAnyPublisher()
        ]
        
        Publishers.MergeMany(group1)
            .merge(with: Publishers.MergeMany(group2))
            .merge(with: Publishers.MergeMany(group3))
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }
    
    func updateStatusItem() {
        guard let button = statusItem?.button, let hostingView = hostingView else { return }
        
        button.image = nil
        button.title = ""
        
        let fittingSize = hostingView.fittingSize
        statusItem?.length = max(22, fittingSize.width)
    }
    
    func showDragLabel(_ label: String) {
        temporaryDragLabel = label
        appState.temporaryDragLabel = label
        updateStatusItem()
    }
    
    func clearDragLabel() {
        temporaryDragLabel = nil
        appState.temporaryDragLabel = nil
        updateStatusItem()
    }
    
    private func getDeviceStatusText() -> String? {
        // Kept for backward compatibility/reference but handled by SwiftUI view
        return nil
    }
    
    func togglePopover() {
        if menubarPanel?.isVisible == true {
            hidePopover()
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
        guard let button = statusItem?.button else { return }
        
        if menubarPanel == nil {
            let contentView = MenubarView().environmentObject(appState)
            menubarPanel = MenubarPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 1), rootView: contentView)
        }
        
        guard let panel = menubarPanel else { return }
        
        if !panel.isVisible {
            // Update content size
            if let hostingView = panel.contentView {
                let size = hostingView.fittingSize
                panel.setContentSize(size)
            }
            
            // Position panel
            let buttonFrame = button.window?.frame ?? .zero
            let panelFrame = panel.frame
            
            let x = buttonFrame.origin.x + (buttonFrame.width / 2) - (panelFrame.width / 2)
            let y = buttonFrame.origin.y - panelFrame.height - 5
            
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            
            DispatchQueue.main.async {
                panel.makeKeyAndOrderFront(nil)
            }

            appState.isMenubarWindowOpen = true
            
            // Monitor clicks outside to close
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let eventLocation = NSEvent.mouseLocation as NSPoint?,
                   let panelFrame = self?.menubarPanel?.frame,
                   !NSMouseInRect(eventLocation, panelFrame, false) {
                    self?.hidePopover()
                }
            }
        }
    }
    
    func hidePopover() {
        menubarPanel?.orderOut(nil)
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

// MARK: - Click-Through Hosting View Subclass
class ClickThroughHostingView: NSHostingView<MenubarStatusView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - Menubar Status View
struct MenubarStatusView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var bleManager = BLECentralManager.shared
    
    var body: some View {
        HStack(spacing: 6) {
            let isConnected = appState.device != nil || bleManager.isAuthenticated
            
            // 1. Primary Icon
            if appState.showMenubarIcon {
                let iconName = isConnected ? "iphone.gen3" : "iphone.slash"
                Image(systemName: iconName)
                    .font(.system(size: appState.menubarFontSize))
                    .imageScale(.medium)
            }
            
            if isConnected {
                // 2. Status Text / Details
                if appState.showMenubarText {
                    if let dragLabel = appState.temporaryDragLabel {
                        Text(dragLabel)
                            .font(.system(size: appState.menubarFontSize, weight: .medium))
                    } else {
                        HStack(spacing: 5) {
                            // Left part: Device Name or Music Info
                            let showMusic = appState.showMenubarMusicIcon && (appState.status?.music?.isPlaying ?? false)
                            
                            if appState.showMenubarCallDetails, let callEvent = appState.activeCall {
                                HStack(spacing: 4) {
                                    if let photoString = callEvent.contactPhoto,
                                       !photoString.isEmpty,
                                       let data = Data(base64Encoded: photoString, options: .ignoreUnknownCharacters) ?? Data(base64Encoded: photoString),
                                       let nsImage = NSImage(data: data) {
                                        let avatarSize = appState.menubarFontSize + 2
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: avatarSize, height: avatarSize)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: callEvent.direction == .incoming ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                                            .font(.system(size: appState.menubarFontSize))
                                            .foregroundColor(.green)
                                    }
                                    
                                    Text(callEvent.contactName)
                                        .font(.system(size: appState.menubarFontSize, weight: .medium))
                                        .lineLimit(1)
                                    
                                    Text("•")
                                        .font(.system(size: appState.menubarFontSize))
                                        .foregroundColor(.secondary)
                                    
                                    Text(formatCallDuration(seconds: appState.activeCallDurationSec))
                                        .font(.system(size: appState.menubarFontSize, design: .monospaced))
                                        .layoutPriority(1)
                                }
                            } else if showMusic, let music = appState.status?.music {
                                let title = music.title.isEmpty ? "Unknown Title" : music.title
                                let artist = music.artist.isEmpty ? "Unknown Artist" : music.artist
                                let musicText = truncate(text: "\(title) - \(artist)")
                                
                                HStack(spacing: 3) {
                                    if appState.showMenubarAlbumArt,
                                       !music.albumArt.isEmpty,
                                       let data = Data(base64Encoded: music.albumArt.stripBase64Prefix()) ?? Data(base64Encoded: music.albumArt),
                                       let nsImage = NSImage(data: data) {
                                        let albumArtSize = appState.menubarFontSize + 2
                                        let cornerRadius = albumArtSize * 3 / 14
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: albumArtSize, height: albumArtSize)
                                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                    } else {
                                        Image(systemName: "music.note")
                                            .font(.system(size: appState.menubarFontSize))
                                            .foregroundColor(.accentColor)
                                    }
                                    Text(musicText)
                                        .font(.system(size: appState.menubarFontSize))
                                }
                            } else if appState.showMenubarDeviceName {
                                let deviceName = appState.device?.name ?? (bleManager.isAuthenticated ? bleManager.connectedDeviceName : nil) ?? ""
                                if !deviceName.isEmpty {
                                    Text(truncate(text: deviceName))
                                        .font(.system(size: appState.menubarFontSize, weight: .medium))
                                }
                            }
                            
                            // Right part: Battery
                            if let battery = appState.status?.battery {
                                let style = appState.menubarBatteryStyle
                                HStack(spacing: 3) {
                                    // Show separator if there was a prefix shown
                                    let hasPrefix = showMusic || (appState.showMenubarDeviceName && !(appState.device?.name ?? bleManager.connectedDeviceName ?? "").isEmpty)
                                    if hasPrefix {
                                        Text("•")
                                            .font(.system(size: appState.menubarFontSize))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if style == "icon" || style == "both" {
                                        Image(systemName: getBatteryIconName(level: battery.level, isCharging: battery.isCharging))
                                            .font(.system(size: appState.menubarFontSize))
                                            .foregroundColor(batteryColor(level: battery.level, isCharging: battery.isCharging))
                                    }
                                    
                                    if style == "percentage" || style == "both" {
                                        Text("\(battery.level)%")
                                            .font(.system(size: appState.menubarFontSize - 1, design: .monospaced))
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 3. Unread Badge Count
                if appState.menubarNotificationStyle == "both" || appState.menubarNotificationStyle == "count" {
                    let unreadCount = appState.notifications.count
                    if unreadCount > 0 {
                        if appState.menubarUnreadBadgeStyle == "badge" {
                            Text("\(unreadCount)")
                                .font(.system(size: appState.menubarFontSize - 3, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, max(4, appState.menubarFontSize * 5 / 12))
                                .padding(.vertical, max(1, appState.menubarFontSize * 1 / 12))
                                .background(badgeColor)
                                .clipShape(Capsule())
                        } else if appState.menubarUnreadBadgeStyle == "text" {
                            Text("\(unreadCount)*")
                                .font(.system(size: appState.menubarFontSize - 1, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 4. Recent Notification Icons
                if appState.menubarNotificationStyle == "both" || appState.menubarNotificationStyle == "icons" {
                    let recentPackages = appState.recentNotifyingPackages
                    if !recentPackages.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(recentPackages, id: \.self) { package in
                                let appIconSize = appState.menubarFontSize + 2
                                let appCornerRadius = appIconSize * 3 / 14
                                if let path = appState.androidApps[package]?.iconUrl,
                                   let image = Image(filePath: path) {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: appIconSize, height: appIconSize)
                                        .clipShape(RoundedRectangle(cornerRadius: appCornerRadius))
                                } else {
                                    Image(systemName: "app.badge")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: appIconSize, height: appIconSize)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, appState.showMenubarPillStroke ? 8 : 4)
        .frame(height: 22)
        .background(
            Group {
                if appState.showMenubarPillStroke {
                    let hasCall = appState.activeCall != nil
                    Capsule()
                        .stroke(
                            hasCall ? Color.accentColor : Color.primary.opacity(0.18),
                            lineWidth: hasCall ? 2.0 : 1.0
                        )
                }
            }
        )
    }
    
    
    
    private var badgeColor: Color {
        switch appState.menubarUnreadBadgeColor {
        case "accent": return .accentColor
        case "red": return .red
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "gray": return .gray
        default: return .accentColor
        }
    }
    
    private func batteryColor(level: Int, isCharging: Bool) -> Color {
        if level < 20 {
            return .yellow
        } else {
            return .primary
        }
    }
    
    private func getBatteryIconName(level: Int, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100.bolt"
        } else if level >= 88 {
            return "battery.100"
        } else if level >= 62 {
            return "battery.75"
        } else if level >= 38 {
            return "battery.50"
        } else if level >= 12 {
            return "battery.25"
        } else {
            return "battery.0"
        }
    }
    
    private func formatCallDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private func truncate(text: String) -> String {
        let maxLength = appState.menubarTextMaxLength
        if text.count > maxLength {
            return String(text.prefix(maxLength - 1)) + "…"
        }
        return text
    }
}
