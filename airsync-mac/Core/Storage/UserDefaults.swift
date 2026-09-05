//
//  UserDefaults.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-10.
//

import Foundation

extension UserDefaults {
    private enum Keys {
        static let lastLicenseCheckDate = "lastLicenseCheckDate"
        static let lastLicenseSuccessfulCheckDate = "lastLicenseSuccessfulCheckDate"
        static let consecutiveLicenseFailCount = "consecutiveLicenseFailCount"
        static let consecutiveNetworkFailureDays = "consecutiveNetworkFailureDays"
        static let scrcpyOnTop = "scrcpyOnTop"
        static let scrcpyDesktopDpi = "scrcpyDesktopDpi"
        static let lastADBCommand = "lastADBCommand"
        static let stayAwake = "stayAwake"
        static let turnScreenOff = "turnScreenOff"
        static let noAudio = "noAudio"
        static let hasPairedDeviceOnce = "hasPairedDeviceOnce"
        static let manualPosition = "manualPosition"
        static let manualPositionCoords = "manualPositionCoords"
        static let continueApp = "continueApp"
        static let directKeyInput = "directKeyInput"
        static let sendNowPlayingStatus = "sendNowPlayingStatus"
        static let syncAndroidPlaybackSeekbar = "syncAndroidPlaybackSeekbar"
        static let showInControlCenter = "showInControlCenter"
        static let isMusicCardHidden = "isMusicCardHidden"
        static let lastOnboarding = "lastOnboarding"
        static let popupSharedImages = "popupSharedImages"
        static let sharedImagePopupsLimit = "sharedImagePopupsLimit"
        static let popupSharedImagesOnLeft = "popupSharedImagesOnLeft"

        static let notificationStacks = "notificationStacks"
        static let trialToken = "trialToken"
        static let trialExpiryDate = "trialExpiryDate"
        static let trialDeviceIdentifier = "trialDeviceIdentifier"
        static let trialLastSync = "trialLastSync"
        static let appSilentNotifications = "appSilentNotifications"
    }

    var consecutiveLicenseFailCount: Int {
        get { integer(forKey: Keys.consecutiveLicenseFailCount) }
        set { set(newValue, forKey: Keys.consecutiveLicenseFailCount) }
    }

    var lastLicenseCheckDate: Date? {
        get { object(forKey: Keys.lastLicenseCheckDate) as? Date }
        set { set(newValue, forKey: Keys.lastLicenseCheckDate) }
    }

    var lastLicenseSuccessfulCheckDate: Date? {
        get { object(forKey: Keys.lastLicenseSuccessfulCheckDate) as? Date }
        set { set(newValue, forKey: Keys.lastLicenseSuccessfulCheckDate) }
    }

    var consecutiveNetworkFailureDays: Int {
        get { integer(forKey: Keys.consecutiveNetworkFailureDays) }
        set { set(newValue, forKey: Keys.consecutiveNetworkFailureDays) }
    }

    var scrcpyOnTop: Bool {
        get { bool(forKey: Keys.scrcpyOnTop)}
        set { set(newValue, forKey: Keys.scrcpyOnTop)}
    }

    var scrcpyDesktopDpi: String {
        get { string(forKey: Keys.scrcpyDesktopDpi) ?? "192" }
        set { set(newValue, forKey: Keys.scrcpyDesktopDpi) }
    }

    var lastADBCommand: String? {
        get { object(forKey: Keys.lastADBCommand) as? String }
        set { set(newValue, forKey: Keys.lastADBCommand) }
    }

    var manualPositionCoords: [String] {
        get {
            return object(forKey: Keys.manualPositionCoords) as? [String] ?? ["0", "0"]
        }
        set {
            set(newValue, forKey: Keys.manualPositionCoords)
        }
    }

    var stayAwake: Bool {
        get { bool(forKey: Keys.stayAwake)}
        set { set(newValue, forKey: Keys.stayAwake)}
    }

    var turnScreenOff: Bool {
        get { bool(forKey: Keys.turnScreenOff)}
        set { set(newValue, forKey: Keys.turnScreenOff)}
    }

    var noAudio: Bool {
        get { bool(forKey: Keys.noAudio)}
        set { set(newValue, forKey: Keys.noAudio)}
    }

    var manualPosition: Bool {
        get { bool(forKey: Keys.manualPosition)}
        set { set(newValue, forKey: Keys.manualPosition)}
    }

    var hasPairedDeviceOnce: Bool {
        get { bool(forKey: Keys.hasPairedDeviceOnce) }
        set { set(newValue, forKey: Keys.hasPairedDeviceOnce) }
    }

    var notificationStacks: Bool {
        get { bool(forKey: Keys.notificationStacks)}
        set { set(newValue, forKey: Keys.notificationStacks)}
    }

    var continueApp: Bool {
        get { bool(forKey: Keys.continueApp)}
        set { set(newValue, forKey: Keys.continueApp)}
    }

    var directKeyInput: Bool {
        get { bool(forKey: Keys.directKeyInput)}
        set { set(newValue, forKey: Keys.directKeyInput)}
    }
    
    var sendNowPlayingStatus: Bool {
        get { bool(forKey: Keys.sendNowPlayingStatus)}
        set { set(newValue, forKey: Keys.sendNowPlayingStatus)}
    }

    /// When enabled, AirSync plays a silent audio loop to claim macOS Now Playing focus,
    /// allowing the Android playback seekbar to be exposed in boringNotch / Control Center.
    /// Disabled by default because it causes Bluetooth multipoint headphones to route
    /// audio to the Mac, preventing Android media from playing through the headphones.
    var syncAndroidPlaybackSeekbar: Bool {
        get { bool(forKey: Keys.syncAndroidPlaybackSeekbar) }
        set { set(newValue, forKey: Keys.syncAndroidPlaybackSeekbar) }
    }

    /// Controls whether Android media info is published to macOS Control Center / boringNotch
    /// via a silent background audio track. Off by default due to Bluetooth multipoint side-effects.
    var showInControlCenter: Bool {
        get { bool(forKey: Keys.showInControlCenter) }
        set { set(newValue, forKey: Keys.showInControlCenter) }
    }

    var isMusicCardHidden: Bool {
        get { bool(forKey: Keys.isMusicCardHidden) }
        set { set(newValue, forKey: Keys.isMusicCardHidden) }
    }

    var popupSharedImages: Bool {
        get { object(forKey: Keys.popupSharedImages) == nil ? true : bool(forKey: Keys.popupSharedImages) }
        set { set(newValue, forKey: Keys.popupSharedImages) }
    }

    var sharedImagePopupsLimit: Int {
        get {
            let val = integer(forKey: Keys.sharedImagePopupsLimit)
            return val == 0 ? 3 : val
        }
        set { set(newValue, forKey: Keys.sharedImagePopupsLimit) }
    }

    var popupSharedImagesOnLeft: Bool {
        get { bool(forKey: Keys.popupSharedImagesOnLeft) }
        set { set(newValue, forKey: Keys.popupSharedImagesOnLeft) }
    }

    var trialToken: String? {
        get { string(forKey: Keys.trialToken) }
        set { set(newValue, forKey: Keys.trialToken) }
    }

    var trialExpiryDate: Date? {
        get { object(forKey: Keys.trialExpiryDate) as? Date }
        set { set(newValue, forKey: Keys.trialExpiryDate) }
    }

    var trialDeviceIdentifier: String? {
        get { string(forKey: Keys.trialDeviceIdentifier) }
        set { set(newValue, forKey: Keys.trialDeviceIdentifier) }
    }

    var trialLastSync: Date? {
        get { object(forKey: Keys.trialLastSync) as? Date }
        set { set(newValue, forKey: Keys.trialLastSync) }
    }
    
    var swapCmdAndCtrl: Bool {
        get { object(forKey: "swapCmdAndCtrl") == nil ? true : bool(forKey: "swapCmdAndCtrl") }
        set { set(newValue, forKey: "swapCmdAndCtrl") }
    }

    var showMirrorControls: Bool {
        get { object(forKey: "showMirrorControls") == nil ? true : bool(forKey: "showMirrorControls") }
        set { set(newValue, forKey: "showMirrorControls") }
    }
    
    // MARK: - String-based Onboarding Tracking
    
    var lastOnboarding: String? {
        get { string(forKey: Keys.lastOnboarding) }
        set { set(newValue, forKey: Keys.lastOnboarding) }
    }
    
    var needsOnboarding: Bool {
        let currentForceUpdateKey = Bundle.main.object(forInfoDictionaryKey: "ForceUpdateKey") as? String ?? "001"
        let lastCompletedVersion = lastOnboarding
        
        // Show onboarding if:
        // 1. No lastOnboarding value exists (first time user)
        // 2. lastOnboarding doesn't match current ForceUpdateKey
        return lastCompletedVersion == nil || lastCompletedVersion != currentForceUpdateKey
    }
    
    var isReturningUser: Bool {
        return lastOnboarding != nil
    }
    
    func markOnboardingCompleted() {
        let currentForceUpdateKey = Bundle.main.object(forInfoDictionaryKey: "ForceUpdateKey") as? String ?? "001"
        lastOnboarding = currentForceUpdateKey
    }
    
    func resetOnboarding() {
        lastOnboarding = "000"
    }

    var appSilentNotifications: [String: Bool] {
        get { dictionary(forKey: Keys.appSilentNotifications) as? [String: Bool] ?? [:] }
        set { set(newValue, forKey: Keys.appSilentNotifications) }
    }
}

