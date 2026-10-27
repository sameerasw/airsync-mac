//
//  QuickShareManager.swift
//  AirSync
//

import Foundation
import SwiftUI
import UserNotifications
@preconcurrency import Combine
import UniformTypeIdentifiers

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
        case connecting(String) // deviceID
        case awaitingPin(String, String) // pin, deviceID
        case sending(String) // deviceID
        case receiving(String) // transferID
        case incomingAwaitingConsent(TransferMetadata, RemoteDeviceInfo)
        case finished
        case failed(String)
    }
    
    private var activeIncomingTransfers: [String: QuickShareTransferInfo] = [:]

    // Android advertises a fresh endpoint each session and stale mDNS records can linger,
    // so one phone may show up under several endpoint IDs. Newest is last.
    private var endpointsByName: [String: [RemoteDeviceInfo]] = [:]
    private var sendTargetName: String?
    private var triedEndpointIDs: Set<String> = []
    private var autoTargetTask: Task<Void, Never>?
    
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
        endpointsByName.removeAll()
        resetSendTarget()
        autoTargetTask?.cancel()
        autoTargetTask = nil
        self.autoTargetDeviceName = autoTargetName
        transferState = .discovering
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
        NearbyConnectionManager.shared.startDeviceDiscovery()
        
        // Trigger Quick Share mode on any connected AirSync device
        WebSocketServer.shared.sendQuickShareTrigger()
    }
    
    public func stopDiscovery() {
        NearbyConnectionManager.shared.stopDeviceDiscovery()
        NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
        discoveredDevices.removeAll()
        endpointsByName.removeAll()
        resetSendTarget()
        autoTargetTask?.cancel()
        autoTargetTask = nil
        self.autoTargetDeviceName = nil
        
        switch transferState {
        case .discovering, .connecting, .awaitingPin, .sending, .receiving, .incomingAwaitingConsent:
            cancelActiveTransfer()
        default:
            break
        }
    }

    private func removeStagedShareFiles() {
        for url in transferURLs where url.pathComponents.contains("AirSyncShares") {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    public func cancelActiveTransfer() {
        resetSendTarget()
        removeStagedShareFiles()
        switch transferState {
        case .connecting(let id), .awaitingPin(_, let id), .sending(let id):
            NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id)
            transferState = .idle
            AppState.shared.showingQuickShareTransfer = false
        case .receiving(let id):
            NearbyConnectionManager.shared.cancelIncomingTransfer(id: id)
            transferState = .idle
            AppState.shared.showingQuickShareTransfer = false
        case let .incomingAwaitingConsent(meta, _):
            NearbyConnectionManager.shared.cancelIncomingTransfer(id: meta.id)
            transferState = .idle
            AppState.shared.showingQuickShareTransfer = false
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + meta.id])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["transfer_" + meta.id])
        default:
            transferState = .idle
            AppState.shared.showingQuickShareTransfer = false
        }
    }

    public func sendFiles(urls: [URL], to device: RemoteDeviceInfo) {
        autoTargetTask?.cancel()
        autoTargetTask = nil
        sendTargetName = device.name
        triedEndpointIDs = []
        transferURLs = urls
        transferProgress = 0
        connect(to: device)
    }

    private func resetSendTarget() {
        sendTargetName = nil
        triedEndpointIDs = []
    }

    /// Endpoints can appear mid-attempt (the phone re-advertises after our trigger), so look them up fresh.
    private func nextUntriedEndpoint() -> RemoteDeviceInfo? {
        guard let name = sendTargetName else { return nil }
        return endpointsByName[name]?.last { $0.id.map { !triedEndpointIDs.contains($0) } ?? false }
    }

    private func connect(to device: RemoteDeviceInfo) {
        guard let deviceID = device.id else { return }
        triedEndpointIDs.insert(deviceID)
        print("[quickshare] Connecting to '\(device.name)' via endpoint \(deviceID)")
        transferState = .connecting(deviceID)
        NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: deviceID, delegate: self, urls: transferURLs)
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

        let fileStr: String = {
            if let textTitle = transfer.textDescription {
                return textTitle
            } else if transfer.files.count == 1 {
                return transfer.files[0].name
            } else {
                return String(format: Localizer.shared.text("quickshare.n_files"), transfer.files.count)
            }
        }()
        
        self.transferState = .incomingAwaitingConsent(transfer, device)
        AppState.shared.showingQuickShareTransfer = true
        
        let content = UNMutableNotificationContent()
        content.title = Localizer.shared.text("app.name")
        content.subtitle = String(format: Localizer.shared.text("quickshare.pin_code"), transfer.pinCode ?? "")
        content.body = String(format: Localizer.shared.text("quickshare.device_sending_files"), device.name, fileStr)
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Submarine.aiff"))
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
            
            self.transferState = .failed(error.localizedDescription)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AppState.shared.showingQuickShareTransfer = false
                self.transferState = .idle
            }
        }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["transfer_" + id])
        activeIncomingTransfers.removeValue(forKey: id)
    }
 
    public func transferDidComplete(id: String, urls: [URL]) {
        print("[quickshare] Transfer \(id) completed on disk with urls: \(urls)")
        self.transferState = .finished
        self.transferProgress = 1.0
        
        // Pop up overlay if enabled and exactly one file transferred
        if AppState.shared.popupSharedImages, urls.count == 1, let firstURL = urls.first {
            DispatchQueue.main.async {
                SharedImagePopupManager.shared.show(fileURL: firstURL)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            AppState.shared.showingQuickShareTransfer = false
            self.transferState = .idle
        }
    }
    
    private func isImage(url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .image)
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
    
    public func handleUserConsent(transferID: String, accepted: Bool) {
        NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
        if !accepted {
            activeIncomingTransfers.removeValue(forKey: transferID)
            if case .incomingAwaitingConsent(let meta, _) = transferState, meta.id == transferID {
                transferState = .idle
                AppState.shared.showingQuickShareTransfer = false
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + transferID])
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["transfer_" + transferID])
            }
        } else {
            if case .incomingAwaitingConsent(let meta, _) = transferState, meta.id == transferID {
                transferState = .receiving(transferID)
                transferProgress = 0
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + transferID])
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["transfer_" + transferID])
            }
        }
    }
    
    public func incomingTransferProgress(id: String, progress: Double) {
        self.transferProgress = progress
        if case .receiving(let activeID) = transferState, activeID == id {
            // Already in receiving state
        } else {
            transferState = .receiving(id)
        }
    }
    
    // MARK: - ShareExtensionDelegate (Outgoing)
    
    public func addDevice(device: RemoteDeviceInfo) {
        var endpoints = endpointsByName[device.name] ?? []
        endpoints.removeAll { $0.id == device.id }
        endpoints.append(device)
        endpointsByName[device.name] = endpoints
        showNewestEndpoint(named: device.name)

        // Wait briefly so a stale cached record doesn't win over the live one
        if let targetName = autoTargetDeviceName, device.name == targetName, autoTargetTask == nil {
            print("[quickshare] Auto-targeting found device '\(device.name)', starting transfer")
            autoTargetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled, self.transferState == .discovering,
                      let newest = self.endpointsByName[targetName]?.last else { return }
                self.autoTargetDeviceName = nil
                self.autoTargetTask = nil
                self.sendFiles(urls: self.transferURLs, to: newest)
            }
        }
    }

    public func removeDevice(id: String) {
        guard let name = endpointsByName.first(where: { $0.value.contains { $0.id == id } })?.key else { return }
        endpointsByName[name]?.removeAll { $0.id == id }
        if endpointsByName[name]?.isEmpty == true {
            endpointsByName[name] = nil
        }
        showNewestEndpoint(named: name)
    }

    private func showNewestEndpoint(named name: String) {
        let index = discoveredDevices.firstIndex { $0.name == name }
        switch (index, endpointsByName[name]?.last) {
        case let (index?, newest?):
            discoveredDevices[index] = newest
        case let (nil, newest?):
            discoveredDevices.append(newest)
        case let (index?, nil):
            discoveredDevices.remove(at: index)
        case (nil, nil):
            break
        }
    }
    
    public func startTransferWithQrCode(device: RemoteDeviceInfo) {
        addDevice(device: device)
    }
    
    public func connectionWasEstablished(pinCode: String) {
        let deviceID = caseDiscoveryID() ?? "unknown"
        lastPinCode = pinCode
        transferState = .awaitingPin(pinCode, deviceID)
    }

    private func caseDiscoveryID() -> String? {
        switch transferState {
        case .connecting(let id), .awaitingPin(_, let id), .sending(let id):
            return id
        default:
            return nil
        }
    }
    
    public func connectionFailed(with error: Error) {
        if case .connecting(let failedID) = transferState, let next = nextUntriedEndpoint() {
            print("[quickshare] Endpoint \(failedID) unreachable, trying \(next.id ?? "?")")
            connect(to: next)
            return
        }
        resetSendTarget()
        transferState = .failed(error.localizedDescription)
        removeStagedShareFiles()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AppState.shared.showingQuickShareTransfer = false
            self.transferState = .idle
        }
    }
    
    public func transferAccepted() {
        if let id = caseDiscoveryID() {
            transferState = .sending(id)
        }
    }
    
    public func transferProgress(progress: Double) {
        self.transferProgress = progress
    }
    
    public func transferFinished() {
        transferState = .finished
        removeStagedShareFiles()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AppState.shared.showingQuickShareTransfer = false
            self.transferState = .idle
        }
    }
}
