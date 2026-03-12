//
//  QuickShareManager.swift
//  AirSync
//

import Foundation
import SwiftUI
import UserNotifications
@preconcurrency import Combine

struct QuickShareTransferInfo {
    let device: RemoteDeviceInfo
    let transfer: TransferMetadata
}

@MainActor
public class QuickShareManager: NSObject, ObservableObject, MainAppDelegate, ShareExtensionDelegate {
    public static let shared = QuickShareManager()
    @Published public var isEnabled: Bool = UserDefaults.standard.bool(forKey: "quickShareEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "quickShareEnabled")
            if isEnabled {
                startService()
            } else {
                stopService()
            }
        }
    }
    
    @Published public var isRunning: Bool = false
    @Published public var discoveredDevices: [RemoteDeviceInfo] = []
    @Published public var transferState: TransferState = .idle
    @Published public var transferProgress: Double = 0
    @Published public var lastPinCode: String?
    @Published public var transferURLs: [URL] = []
    @Published public var autoTargetDeviceName: String?
    
    public enum TransferState: Equatable {
        case idle
        case discovering
        case connecting
        case awaitingPin(String)
        case sending
        case finished
        case failed(String)
    }
    
    private var activeIncomingTransfers: [String: QuickShareTransferInfo] = [:]
    
    override private init() {
        super.init()
        NearbyConnectionManager.shared.mainAppDelegate = self
        if isEnabled {
            startService()
        }
    }
    
    public var deviceName: String {
        return UserDefaults.standard.string(forKey: "deviceName") ?? Host.current().localizedName ?? "Mac"
    }
    
    // MARK: - Lifecycle
    
    public func startService() {
        guard !isRunning else { return }
        registerNotificationCategories()
        NearbyConnectionManager.shared.mainAppDelegate = self
        NearbyConnectionManager.shared.becomeVisible()
        isRunning = true
        print("[quickshare] Service started — visible as '\(deviceName)'")
    }
    
    public func stopService() {
        isRunning = false
        // Currently NearbyConnectionManager doesn't have a stopVisibility, 
        // but we can at least stop discovery and incoming handles
        print("[quickshare] Service stopped")
    }
    
    private func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        let acceptAction = UNNotificationAction(
            identifier: "QUICKSHARE_ACCEPT",
            title: Localizer.shared.text("quickshare.accept"),
            options: .authenticationRequired
        )
        let declineAction = UNNotificationAction(
            identifier: "QUICKSHARE_DECLINE",
            title: Localizer.shared.text("quickshare.decline")
        )
        let incomingCategory = UNNotificationCategory(
            identifier: "INCOMING_TRANSFERS",
            actions: [acceptAction, declineAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([incomingCategory])
    }
    
    // MARK: - Outbound Discovery
    
    public func startDiscovery(autoTargetName: String? = nil) {
        discoveredDevices.removeAll()
        transferURLs.removeAll() // Clear old URLs
        self.autoTargetDeviceName = autoTargetName
        transferState = .discovering
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
        NearbyConnectionManager.shared.startDeviceDiscovery()
    }
    
    public func stopDiscovery() {
        NearbyConnectionManager.shared.stopDeviceDiscovery()
        NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
        discoveredDevices.removeAll()
        self.autoTargetDeviceName = nil
        if transferState == .discovering {
            transferState = .idle
        }
    }

    public func sendFiles(urls: [URL], to device: RemoteDeviceInfo) {
        transferState = .connecting
        transferProgress = 0
        NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: device.id!, delegate: self, urls: urls)
    }
    
    public func generateQrCodeKey() -> String {
        return NearbyConnectionManager.shared.generateQrCodeKey()
    }
    
    public func clearQrCodeKey() {
        NearbyConnectionManager.shared.clearQrCodeKey()
    }
    
    // MARK: - MainAppDelegate (Incoming)
    
    public func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
        // Auto-accept if enabled and sender matches connected device
        if AppState.shared.autoAcceptQuickShare,
           let connectedDeviceName = AppState.shared.device?.name,
           device.name == connectedDeviceName {
            print("[quickshare] Auto-accepting transfer \(transfer.id) from \(device.name)")
            handleUserConsent(transferID: transfer.id, accepted: true)
            return
        }

        let fileStr: String
        if let textTitle = transfer.textDescription {
            fileStr = textTitle
        } else if transfer.files.count == 1 {
            fileStr = transfer.files[0].name
        } else {
            fileStr = String(format: Localizer.shared.text("n_files"), transfer.files.count)
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Quick Share"
        content.subtitle = String(format: Localizer.shared.text("pin_code"), transfer.pinCode ?? "")
        content.body = String(format: Localizer.shared.text("device_sending_files"), device.name, fileStr)
        content.sound = .default
        content.categoryIdentifier = "INCOMING_TRANSFERS"
        content.userInfo = [
            "type": "quickshare",
            "transferID": transfer.id
        ]
        
        content.setValue(false, forKey: "hasDefaultAction")
        
        let request = UNNotificationRequest(identifier: "transfer_" + transfer.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        self.activeIncomingTransfers[transfer.id] = QuickShareTransferInfo(device: device, transfer: transfer)
    }
    
    public func incomingTransfer(id: String, didFinishWith error: Error?) {
        if let error = error {
            let content = UNMutableNotificationContent()
            content.title = Localizer.shared.text("transfer_failed")
            content.body = error.localizedDescription
            content.sound = .default
            let request = UNNotificationRequest(identifier: "transfer_error_" + id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + id])
        activeIncomingTransfers.removeValue(forKey: id)
    }
    
    public func handleUserConsent(transferID: String, accepted: Bool) {
        NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
        if !accepted {
            activeIncomingTransfers.removeValue(forKey: transferID)
        }
    }
    
    // MARK: - ShareExtensionDelegate (Outgoing)
    
    public func addDevice(device: RemoteDeviceInfo) {
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
            
            // If auto-targeting is active and name matches, start transfer
            if let targetName = autoTargetDeviceName, device.name == targetName {
                print("[quickshare] Auto-targeting found device '\(device.name)', starting transfer")
                self.autoTargetDeviceName = nil // Clear so it doesn't trigger again
                sendFiles(urls: self.transferURLs, to: device)
            }
        }
    }
    
    public func removeDevice(id: String) {
        discoveredDevices.removeAll(where: { $0.id == id })
    }
    
    public func startTransferWithQrCode(device: RemoteDeviceInfo) {
        addDevice(device: device)
    }
    
    public func connectionWasEstablished(pinCode: String) {
        lastPinCode = pinCode
        transferState = .awaitingPin(pinCode)
    }
    
    public func connectionFailed(with error: Error) {
        transferState = .failed(error.localizedDescription)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AppState.shared.showingQuickShareTransfer = false
            self.transferState = .idle
        }
    }
    
    public func transferAccepted() {
        transferState = .sending
    }
    
    public func transferProgress(progress: Double) {
        self.transferProgress = progress
    }
    
    public func transferFinished() {
        transferState = .finished
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AppState.shared.showingQuickShareTransfer = false
            self.transferState = .idle
        }
    }
}
