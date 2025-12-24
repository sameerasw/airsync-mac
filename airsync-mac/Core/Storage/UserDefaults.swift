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
        static let scrcpyShareRes = "scrcpyShareRes"
        static let scrcpyDesktopMode = "scrcpyDesktopMode"
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
        static let isMusicCardHidden = "isMusicCardHidden"
        static let lastOnboarding = "lastOnboarding"

        static let notificationStacks = "notificationStacks"
        static let trialToken = "trialToken"
        static let trialExpiryDate = "trialExpiryDate"
        static let trialDeviceIdentifier = "trialDeviceIdentifier"
        static let trialLastSync = "trialLastSync"
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

    var scrcpyShareRes: Bool {
        get { bool(forKey: Keys.scrcpyShareRes)}
        set { set(newValue, forKey: Keys.scrcpyShareRes)}
    }

    var scrcpyDesktopMode: String? {
        get { object(forKey: Keys.scrcpyDesktopMode) as? String }
        set { set(newValue, forKey: Keys.scrcpyDesktopMode) }
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

    var isMusicCardHidden: Bool {
        get { bool(forKey: Keys.isMusicCardHidden) }
        set { set(newValue, forKey: Keys.isMusicCardHidden) }
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
}

