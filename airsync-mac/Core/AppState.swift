//
//  AppState.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//
import SwiftUI
import Foundation
import Cocoa
internal import Combine
import UserNotifications

class AppState: ObservableObject {
    static let shared = AppState()

    private var clipboardCancellable: AnyCancellable?
    private var lastClipboardValue: String? = nil
    private var shouldSkipSave = false
    private let licenseDetailsKey = "licenseDetails"

    @Published var isOS26: Bool = true

    init() {
        self.isPlus = UserDefaults.standard.bool(forKey: "isPlus")

        // Load from UserDefaults
        let name = UserDefaults.standard.string(forKey: "deviceName") ?? (Host.current().localizedName ?? "My Mac")
        let portString = UserDefaults.standard.string(forKey: "devicePort") ?? String(Defaults.serverPort)
        let port = Int(portString) ?? Int(Defaults.serverPort)
        let adbPortValue = UserDefaults.standard.integer(forKey: "adbPort")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"

        self.adbPort = adbPortValue == 0 ? 5555 : UInt16(adbPortValue)
        self.mirroringPlus = UserDefaults.standard.bool(forKey: "mirroringPlus")
        self.adbEnabled = UserDefaults.standard.bool(forKey: "adbEnabled")
        self.showMenubarText = UserDefaults.standard.bool(forKey: "showMenubarText")

        // Default to true if not previously set
        let showNameObj = UserDefaults.standard.object(forKey: "showMenubarDeviceName")
        self.showMenubarDeviceName = showNameObj == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showMenubarDeviceName")

        let savedMaxLength = UserDefaults.standard.integer(forKey: "menubarTextMaxLength")
        self.menubarTextMaxLength = savedMaxLength > 0 ? savedMaxLength : 30

        self.isClipboardSyncEnabled = UserDefaults.standard.bool(forKey: "isClipboardSyncEnabled")
        self.windowOpacity = UserDefaults.standard
            .double(forKey: "windowOpacity")
        self.hideDockIcon = UserDefaults.standard
            .bool(forKey: "hideDockIcon")
        self.alwaysOpenWindow = UserDefaults.standard
            .bool(forKey: "alwaysOpenWindow")
        self.notificationSound = UserDefaults.standard
            .string(forKey: "notificationSound") ?? "default"
        self.dismissNotif = UserDefaults.standard
            .bool(forKey: "dismissNotif")
        
        // Default to true for backward compatibility - existing behavior should continue
        let savedNowPlayingStatus = UserDefaults.standard.object(forKey: "sendNowPlayingStatus")
        self.sendNowPlayingStatus = savedNowPlayingStatus == nil ? true : UserDefaults.standard.bool(forKey: "sendNowPlayingStatus")
        
        // Auto-open links defaults to false
        self.autoOpenLinks = UserDefaults.standard.bool(forKey: "autoOpenLinks")
        
        if isClipboardSyncEnabled {
            startClipboardMonitoring()
        }

        #if SELF_COMPILED
        self.isPlus = true
        UserDefaults.standard.set(true, forKey: "isPlus")
        UserDefaults.standard.lastLicenseSuccessfulCheckDate = Date().addingTimeInterval(-(24 * 60 * 60))
        #else
        Task {
            await Gumroad().checkLicenseIfNeeded()
        }
        #endif

        self.scrcpyBitrate = UserDefaults.standard.integer(forKey: "scrcpyBitrate")
        if self.scrcpyBitrate == 0 { self.scrcpyBitrate = 4 }

        self.scrcpyResolution = UserDefaults.standard.integer(forKey: "scrcpyResolution")
        if self.scrcpyResolution == 0 { self.scrcpyResolution = 1200 }

    // Initialize persisted UI toggles
    self.isMusicCardHidden = UserDefaults.standard.bool(forKey: "isMusicCardHidden")


        // Load and validate saved network adapter
        let savedAdapterName = UserDefaults.standard.string(forKey: "selectedNetworkAdapterName")
        self.selectedNetworkAdapterName = validateAndGetNetworkAdapter(savedName: savedAdapterName)

        self.myDevice = Device(
            name: name,
            ipAddress: WebSocketServer.shared
                .getLocalIPAddress(
                    adapterName: selectedNetworkAdapterName
                ) ?? "N/A",
            port: port,
            version:appVersion
        )
        self.licenseDetails = loadLicenseDetailsFromUserDefaults()

        loadAppsFromDisk()
        loadPinnedApps()
        // QuickConnectManager handles its own initialization

//        postNativeNotification(id: "test_notification", appName: "AirSync Beta", title: "Hi there! (っ◕‿◕)っ", body: "Welcome to and thanks for testing out the app. Please don't forget to report issues to sameerasw.com@gmail.com or any other community you prefer. <3", appIcon: nil)
    }

    @Published var minAndroidVersion = Bundle.main.infoDictionary?["AndroidVersion"] as? String ?? "2.0.0"

    @Published var device: Device? = nil {
        didSet {
            // Store the last connected device when a new device connects
            if let newDevice = device {
                QuickConnectManager.shared.saveLastConnectedDevice(newDevice)
                // Validate pinned apps when connecting to a device
                validatePinnedApps()
            }
            
            // Automatically switch to the appropriate tab when device connection state changes
            if device == nil {
                selectedTab = .qr
            } else {
                selectedTab = .notifications
            }
        }
    }
    @Published var notifications: [Notification] = []
    @Published var status: DeviceStatus? = nil
    @Published var myDevice: Device? = nil
    @Published var port: UInt16 = Defaults.serverPort
    @Published var androidApps: [String: AndroidApp] = [:]
    
    @Published var pinnedApps: [PinnedApp] = [] {
        didSet {
            savePinnedApps()
        }
    }

    @Published var deviceWallpapers: [String: String] = [:] // key = deviceName-ip, value = file path
    @Published var isClipboardSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isClipboardSyncEnabled, forKey: "isClipboardSyncEnabled")
            if isClipboardSyncEnabled {
                startClipboardMonitoring()
            } else {
                stopClipboardMonitoring()
            }
        }
    }
    @Published var shouldRefreshQR: Bool = false
    @Published var webSocketStatus: WebSocketStatus = .stopped
    @Published var selectedTab: TabIdentifier = .qr

    @Published var adbConnected: Bool = false
    @Published var adbConnecting: Bool = false
    @Published var currentDeviceWallpaperBase64: String? = nil
    @Published var selectedNetworkAdapterName: String? { // e.g., "en0"
        didSet {
            UserDefaults.standard.set(selectedNetworkAdapterName, forKey: "selectedNetworkAdapterName")
        }
    }
    @Published var showMenubarText: Bool {
        didSet {
            UserDefaults.standard.set(showMenubarText, forKey: "showMenubarText")
        }
    }

    @Published var showMenubarDeviceName: Bool {
        didSet {
            UserDefaults.standard.set(showMenubarDeviceName, forKey: "showMenubarDeviceName")
        }
    }

    @Published var menubarTextMaxLength: Int {
        didSet {
            UserDefaults.standard.set(menubarTextMaxLength, forKey: "menubarTextMaxLength")
        }
    }

    @Published var scrcpyBitrate: Int = 4 {
        didSet {
            UserDefaults.standard.set(scrcpyBitrate, forKey: "scrcpyBitrate")
        }
    }

    @Published var scrcpyResolution: Int = 1200 {
        didSet {
            UserDefaults.standard.set(scrcpyResolution, forKey: "scrcpyResolution")
        }
    }

    @Published var licenseDetails: LicenseDetails? {
        didSet {
            saveLicenseDetailsToUserDefaults()
        }
    }

    @Published var adbPort: UInt16 {
        didSet {
            UserDefaults.standard.set(adbPort, forKey: "adbPort")
        }
    }
    @Published var adbConnectionResult: String? = nil

    @Published var mirroringPlus: Bool {
        didSet {
            UserDefaults.standard.set(mirroringPlus, forKey: "mirroringPlus")
        }
    }

    @Published var adbEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adbEnabled, forKey: "adbEnabled")
        }
    }

    @Published var windowOpacity: Double {
        didSet {
            UserDefaults.standard.set(windowOpacity, forKey: "windowOpacity")
        }
    }

    @Published var hideDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")
            updateDockIconVisibility()
        }
    }

    @Published var alwaysOpenWindow: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOpenWindow, forKey: "alwaysOpenWindow")
        }
    }

    @Published var notificationSound: String {
        didSet {
            UserDefaults.standard.set(notificationSound, forKey: "notificationSound")
        }
    }

    @Published var dismissNotif: Bool {
        didSet {
            UserDefaults.standard.set(dismissNotif, forKey: "dismissNotif")
        }
    }

    @Published var sendNowPlayingStatus: Bool {
        didSet {
            UserDefaults.standard.set(sendNowPlayingStatus, forKey: "sendNowPlayingStatus")
        }
    }

    @Published var autoOpenLinks: Bool {
        didSet {
            UserDefaults.standard.set(autoOpenLinks, forKey: "autoOpenLinks")
        }
    }

    // Whether the media player card is hidden on the PhoneView
    @Published var isMusicCardHidden: Bool = false {
        didSet {
            UserDefaults.standard.set(isMusicCardHidden, forKey: "isMusicCardHidden")
        }
    }

    @Published var isOnboardingActive: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("OnboardingStateChanged"),
                object: nil,
                userInfo: ["isActive": isOnboardingActive]
            )
        }
    }

    // File transfer tracking state
    @Published var transfers: [String: FileTransferSession] = [:]

    // Toggle licensing
    let licenseCheck: Bool = true

    @Published var isPlus: Bool {
        didSet {
            if !shouldSkipSave {
                UserDefaults.standard.set(isPlus, forKey: "isPlus")
            }
            // Notify about license status change for icon revert logic
            NotificationCenter.default.post(name: NSNotification.Name("LicenseStatusChanged"), object: nil)
        }
    }

    func setPlusTemporarily(_ value: Bool) {
        shouldSkipSave = true
        isPlus = value
        shouldSkipSave = false
    }

    // Remove notification by model instance and system notif center
    func removeNotification(_ notif: Notification) {
        DispatchQueue.main.async {
            withAnimation {
                self.notifications.removeAll { $0.id == notif.id }
            }
            if self.dismissNotif {
                WebSocketServer.shared.dismissNotification(id: notif.nid)
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notif.nid])
        }
    }

    func removeNotificationById(_ nid: String) {
        DispatchQueue.main.async {
            withAnimation {
                self.notifications.removeAll { $0.nid == nid }
            }
            if self.dismissNotif {
                WebSocketServer.shared.dismissNotification(id: nid)
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [nid])
        }
    }

    func hideNotification(_ notif: Notification) {
        DispatchQueue.main.async {
            withAnimation {
                self.notifications.removeAll { $0.id == notif.id }
            }
            self.removeNotification(notif)
        }
    }

    func clearNotifications() {
        DispatchQueue.main.async {
            if !self.notifications.isEmpty {
                withAnimation {
                    self.notifications.removeAll()
                }
            }
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }

    func disconnectDevice() {
        DispatchQueue.main.async {
            // Send request to remote device to disconnect
            WebSocketServer.shared.sendDisconnectRequest()

            // Then locally reset state
            self.device = nil
            self.notifications.removeAll()
            self.status = nil
            self.currentDeviceWallpaperBase64 = nil
            self.transfers = [:]

            if self.adbConnected {
                ADBConnector.disconnectADB()
            }
        }
    }

    func addNotification(_ notif: Notification) {
        DispatchQueue.main.async {
            withAnimation {
                self.notifications.insert(notif, at: 0)
            }
            // Trigger native macOS notification
            var appIcon: NSImage? = nil
            if let iconPath = self.androidApps[notif.package]?.iconUrl {
                appIcon = NSImage(contentsOfFile: iconPath)
            }
            self.postNativeNotification(
                id: notif.nid,
                appName: notif.app,
                title: notif.title,
                body: notif.body,
                appIcon: appIcon,
                package: notif.package,
                actions: notif.actions
            )
        }
    }

    func postNativeNotification(
        id: String,
        appName: String,
        title: String,
        body: String,
        appIcon: NSImage? = nil,
        package: String? = nil,
        actions: [NotificationAction] = [],
        extraActions: [UNNotificationAction] = [],
        extraUserInfo: [String: Any] = [:]
    ) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "\(appName) - \(title)"
        content.body = body
        
        // Use custom sound if selected, otherwise use default
        if notificationSound == "default" {
            content.sound = .default
        } else {
            // For system sounds, we need to use the .aiff extension
            content.sound = UNNotificationSound(named: UNNotificationSoundName("\(notificationSound).aiff"))
        }

        content.userInfo["nid"] = id
        if let pkg = package { content.userInfo["package"] = pkg }
        // Merge any extra payload the caller wants to pass
        for (k, v) in extraUserInfo { content.userInfo[k] = v }

        // Build action list (Android actions + optional View action if mirroring conditions)
        let actionDefinitions: [NotificationAction] = actions
        var includeView = false
        if let pkg = package, pkg != "com.sameerasw.airsync", adbConnected, mirroringPlus {
            includeView = true
        }

        // Construct UNNotificationActions
        var unActions: [UNNotificationAction] = []
        for a in actionDefinitions.prefix(8) { // safety cap
            switch a.type {
            case .button:
                unActions.append(UNNotificationAction(identifier: "ACT_\(a.name)", title: a.name, options: []))
            case .reply:
                if #available(macOS 13.0, *) {
                    unActions.append(UNTextInputNotificationAction(identifier: "ACT_\(a.name)", title: a.name, options: [], textInputButtonTitle: "Send", textInputPlaceholder: a.name))
                } else {
                    unActions.append(UNNotificationAction(identifier: "ACT_\(a.name)", title: a.name, options: []))
                }
            }
        }
        if includeView {
            unActions.append(UNNotificationAction(identifier: "VIEW_ACTION", title: "View", options: []))
        }
        // Append caller-provided extra actions (e.g., OPEN_LINK)
        unActions.append(contentsOf: extraActions)

        // Choose category: DEFAULT_CATEGORY when no custom actions besides optional view; otherwise derive
        if unActions.isEmpty {
            content.categoryIdentifier = "DEFAULT_CATEGORY"
            content.userInfo["actions"] = []
            finalizeAndSchedule(center: center, content: content, id: id, appIcon: appIcon)
        } else {
            let actionNamesKey = unActions.map { $0.identifier }.joined(separator: "_")
            let catId = "DYN_\(actionNamesKey)"
            content.categoryIdentifier = catId
            content.userInfo["actions"] = actions.map { ["name": $0.name, "type": $0.type.rawValue] }

            center.getNotificationCategories { existing in
                if existing.first(where: { $0.identifier == catId }) == nil {
                    let newCat = UNNotificationCategory(identifier: catId, actions: unActions, intentIdentifiers: [], options: [])
                    center.setNotificationCategories(existing.union([newCat]))
                }
                self.finalizeAndSchedule(center: center, content: content, id: id, appIcon: appIcon)
            }
        }
    }

    private func finalizeAndSchedule(center: UNUserNotificationCenter, content: UNMutableNotificationContent, id: String, appIcon: NSImage?) {
        // Attach icon
        if let icon = appIcon, let iconFileURL = saveIconToTemporaryFile(icon: icon) {
            if let attachment = try? UNNotificationAttachment(identifier: "appIcon", url: iconFileURL, options: nil) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error { print("[state] (notification) Failed to post native notification: \(error)") }
        }
    }

    private func saveIconToTemporaryFile(icon: NSImage) -> URL? {
        // Save NSImage as a temporary PNG file to attach in notification
        guard let tiffData = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempFile = tempDir.appendingPathComponent("notification_icon_\(UUID().uuidString).png")

        do {
            try pngData.write(to: tempFile)
            return tempFile
        } catch {
            print("[state] Error saving icon to temp file: \(error)")
            return nil
        }
    }

    func syncWithSystemNotifications() {
        UNUserNotificationCenter.current().getDeliveredNotifications { systemNotifs in
            let systemNIDs = Set(systemNotifs.map { $0.request.identifier })

            DispatchQueue.main.async {
                let currentNIDs = Set(self.notifications.map { $0.nid })
                let removedNIDs = currentNIDs.subtracting(systemNIDs)

                for nid in removedNIDs {
                    print("[state] (notification) System notification \(nid) was dismissed manually.")
                    self.removeNotificationById(nid)
                }
            }
        }
    }

    private func startClipboardMonitoring() {
        guard isClipboardSyncEnabled else { return }
        clipboardCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let pasteboard = NSPasteboard.general
                if let copiedString = pasteboard.string(forType: .string),
                   copiedString != self.lastClipboardValue {
                    self.lastClipboardValue = copiedString
                    self.sendClipboardToAndroid(text: copiedString)
                    print("[state] (clipboard) updated :" + copiedString)
                }
            }
    }

    func sendClipboardToAndroid(text: String) {
        let message = """
    {
        "type": "clipboardUpdate",
        "data": {
            "text": "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
        }
    }
    """
        WebSocketServer.shared.sendClipboardUpdate(message)
    }

    func updateClipboardFromAndroid(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastClipboardValue = text

        // Only handle URLs specially if the whole text is a valid http/https URL
        // AND the user has AirSync+ (isPlus). Otherwise show a regular clipboard update.
        if let url = exactURL(from: text), self.isPlus {
            if self.autoOpenLinks {
                // Auto-open the URL without showing a notification
                NSWorkspace.shared.open(url)
            } else {
                // Show "Continue browsing" notification with Open action
                let open = UNNotificationAction(identifier: "OPEN_LINK", title: "Open", options: [])
                self.postNativeNotification(
                    id: "clipboard",
                    appName: "Clipboard",
                    title: "Continue browsing",
                    body: text,
                    extraActions: [open],
                    extraUserInfo: ["url": url.absoluteString]
                )
            }
        } else {
            // Non-plus users or non-URL clipboard content: simple clipboard update notification
            self.postNativeNotification(id: "clipboard", appName: "Clipboard", title: "Updated", body: text)
        }
    }

    private func stopClipboardMonitoring() {
        clipboardCancellable?.cancel()
        clipboardCancellable = nil
    }

    // MARK: - Continue browsing helper (exact URL detection)
    private func exactURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return nil }
        // Ensure no extra text beyond a URL
        if trimmed != text { /* allow surrounding whitespace */ }
        return url
    }

    func wallpaperCacheDirectory() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpapers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var currentWallpaperPath: String? {
        guard let device = myDevice else { return nil }
        let key = "\(device.name)-\(device.ipAddress)"
        return deviceWallpapers[key]
    }

    private func saveLicenseDetailsToUserDefaults() {
        guard let details = licenseDetails else {
            UserDefaults.standard.removeObject(forKey: licenseDetailsKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(details)
            UserDefaults.standard.set(data, forKey: licenseDetailsKey)
        } catch {
            print("[state] (license) Failed to encode license details: \(error)")
        }
    }

    private func loadLicenseDetailsFromUserDefaults() -> LicenseDetails? {
        guard let data = UserDefaults.standard.data(forKey: licenseDetailsKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(LicenseDetails.self, from: data)
        } catch {
            print("[state] (license) Failed to decode license details: \(error)")
            return nil
        }
    }

    func saveAppsToDisk() {
        let url = appIconsDirectory().appendingPathComponent("apps.json")
        do {
            let data = try JSONEncoder().encode(Array(AppState.shared.androidApps.values))
            try data.write(to: url)
        } catch {
            print("[state] (apps) Error saving apps: \(error)")
        }
    }

    func loadAppsFromDisk() {
        let url = appIconsDirectory().appendingPathComponent("apps.json")
        do {
            let data = try Data(contentsOf: url)
            let apps = try JSONDecoder().decode([AndroidApp].self, from: data)
            DispatchQueue.main.async {
                for app in apps {
                    AppState.shared.androidApps[app.packageName] = app
                    if let iconPath = app.iconUrl {
                        AppState.shared
                            .androidApps[app.packageName]?.iconUrl = iconPath
                    }
                }
            }
        } catch {
            print("[state] (apps) Error loading apps: \(error)")
        }
    }

    // MARK: - Pinned Apps Management
    
    func loadPinnedApps() {
        guard let data = UserDefaults.standard.data(forKey: "pinnedApps") else {
            return
        }
        
        do {
            pinnedApps = try JSONDecoder().decode([PinnedApp].self, from: data)
        } catch {
            print("[state] (pinned) Error loading pinned apps: \(error)")
        }
    }
    
    func savePinnedApps() {
        do {
            let data = try JSONEncoder().encode(pinnedApps)
            UserDefaults.standard.set(data, forKey: "pinnedApps")
        } catch {
            print("[state] (pinned) Error saving pinned apps: \(error)")
        }
    }
    
    func addPinnedApp(_ app: AndroidApp) -> Bool {
        // Check if already pinned
        guard !pinnedApps.contains(where: { $0.packageName == app.packageName }) else {
            return false
        }
        
        // Check if under the limit of 3 apps
        guard pinnedApps.count < 3 else {
            return false
        }
        
        let pinnedApp = PinnedApp(packageName: app.packageName, appName: app.name, iconUrl: app.iconUrl)
        pinnedApps.append(pinnedApp)
        return true
    }
    
    func removePinnedApp(_ packageName: String) {
        pinnedApps.removeAll { $0.packageName == packageName }
    }
    
    func validatePinnedApps() {
        // Remove pinned apps that are no longer available
        pinnedApps.removeAll { pinnedApp in
            androidApps[pinnedApp.packageName] == nil
        }
    }

    func updateDockIconVisibility() {
        DispatchQueue.main.async {
            if self.hideDockIcon {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }
    
    /// Revalidates the current network adapter selection and falls back to auto if no longer valid
    func revalidateNetworkAdapter() {
        let currentSelection = selectedNetworkAdapterName
        let validated = validateAndGetNetworkAdapter(savedName: currentSelection)
        
        if currentSelection != validated {
            print("[state] Network adapter changed from '\(currentSelection ?? "auto")' to '\(validated ?? "auto")'")
            selectedNetworkAdapterName = validated
            shouldRefreshQR = true
        }
    }
    
    /// Validates a saved network adapter name and returns it if available with valid IP, otherwise returns nil (auto)
    private func validateAndGetNetworkAdapter(savedName: String?) -> String? {
        guard let savedName = savedName else {
            print("[state] No saved network adapter, using auto selection")
            return nil // Auto mode
        }
        
        // Get available adapters from WebSocketServer
        let availableAdapters = WebSocketServer.shared.getAvailableNetworkAdapters()
        
        // Check if the saved adapter is still available
        guard availableAdapters
            .first(where: { $0.name == savedName }) != nil else {
            print("[state] Saved network adapter '\(savedName)' not found, falling back to auto")
            return nil // Fall back to auto
        }
        
        // Verify the adapter has a valid IP address
        let ipAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: savedName)
        guard let validIP = ipAddress, !validIP.isEmpty, validIP != "127.0.0.1" else {
            print("[state] Saved network adapter '\(savedName)' has no valid IP (\(ipAddress ?? "nil")), falling back to auto")
            return nil // Fall back to auto
        }
        
        print("[state] Using saved network adapter: \(savedName) -> \(validIP)")
        return savedName
    }
}
