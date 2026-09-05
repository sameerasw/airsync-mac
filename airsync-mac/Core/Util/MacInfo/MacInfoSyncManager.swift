//
//  NowPlayingViewModel.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-17.
//
import Foundation
import Combine
import CryptoKit

class MacInfoSyncManager: ObservableObject {
    static let shared = MacInfoSyncManager()
    @Published var title: String = "Unknown Title"
    @Published var artist: String = "Unknown Artist"
    @Published var album: String = "Unknown Album"
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var artworkBase64: String = ""

    private var timer: Timer?
    private var lastSentInfo: NowPlayingInfo?
    // Snapshot of the last payload we actually sent over the wire
    private var lastSentSnapshot: Snapshot?
    
    private var lastSentArtworkHash: String?

    // Mirrors the payload fields we send so equality check is accurate and cheap
    private struct Snapshot: Equatable {
        struct Music: Equatable {
            let isPlaying: Bool
            let title: String
            let artist: String
            let volume: Int
            let isMuted: Bool
            let albumArt: String
            let likeStatus: String
            let elapsedTime: Int
            let duration: Int
        }
        let batteryLevel: Int
        let isCharging: Bool
        let isPaired: Bool
        let music: Music?
    }
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Monitor device connection status and sendNowPlayingStatus toggle
        Publishers.CombineLatest(AppState.shared.$device, AppState.shared.$sendNowPlayingStatus)
            .sink { [weak self] device, sendNowPlayingStatus in
                if device != nil {
                    self?.startSync(sendNowPlayingStatus: sendNowPlayingStatus)
                } else {
                    self?.stopSync()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        stopSync()
        cancellables.removeAll()
    }

    private func startSync(sendNowPlayingStatus: Bool) {
        print("[mac-info-sync] Starting device status monitoring - device connected")

        // Reset retry count on fresh connection
        NowPlayingCLI.shared.resetRetryCount()

        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.refreshBatteryStatus()
            }
        }

        if sendNowPlayingStatus {
            NowPlayingCLI.shared.startStreaming { [weak self] info in
                self?.handleNowPlayingUpdate(info)
            }
            refreshBatteryStatus()
        } else {
            NowPlayingCLI.shared.stopStreaming()
            sendDeviceStatusWithoutMusic()
        }
    }

    private func stopSync() {
        print("[mac-info-sync] Stopping media playback monitoring - device disconnected")
        timer?.invalidate()
        timer = nil

        NowPlayingCLI.shared.stopStreaming()

        // Reset published properties when stopping
        DispatchQueue.main.async {
            self.title = "Unknown Title"
            self.artist = "Unknown Artist"
            self.album = "Unknown Album"
            self.elapsed = 0
            self.duration = 0
            self.isPlaying = false
            self.artworkBase64 = ""
            self.lastSentInfo = nil
            self.lastSentSnapshot = nil
            self.lastSentArtworkHash = nil
        }
    }

    func forceRefresh() {
        refreshStatus()
    }

    private func refreshStatus() {
        guard AppState.shared.device != nil else { return }
        if let lastInfo = lastSentInfo, AppState.shared.sendNowPlayingStatus {
            sendDeviceStatusIfNeeded(with: lastInfo)
        } else {
            sendDeviceStatusWithoutMusic()
        }
    }

    private func refreshBatteryStatus() {
        refreshStatus()
    }

    private func handleNowPlayingUpdate(_ info: NowPlayingInfo?) {
        guard AppState.shared.device != nil else { return }

        guard let info = info else {
            sendDeviceStatusWithoutMusic()
            return
        }

        let ownBundleId = Bundle.main.bundleIdentifier ?? ""
        if let bundleId = info.bundleIdentifier, !ownBundleId.isEmpty, bundleId == ownBundleId {
            sendDeviceStatusWithoutMusic()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.title = info.title ?? "Unknown Title"
            self?.artist = info.artist ?? "Unknown Artist"
            self?.album = info.album ?? "Unknown Album"
            self?.elapsed = info.elapsedTime ?? 0
            self?.duration = info.duration ?? 0
            self?.isPlaying = info.isPlaying ?? false

            self?.sendDeviceStatusIfNeeded(with: info)
        }
    }
    
    private func sendDeviceStatusWithoutMusic() {
        // Only send if there's a connected device
        guard AppState.shared.device != nil else { return }

        // Get battery info
        let batteryInfo = getBatteryInfo()

        // Build snapshot and compare to last sent; skip network if identical
        let snapshot = Snapshot(
            batteryLevel: batteryInfo.level,
            isCharging: batteryInfo.isCharging,
            isPaired: true,
            music: nil
        )

        guard snapshot != lastSentSnapshot else {
            // Nothing changed — skip sending
            return
        }

        // Send device status without music info (full payload for current mode)
        WebSocketServer.shared.sendDeviceStatus(
            batteryLevel: snapshot.batteryLevel,
            isCharging: snapshot.isCharging,
            isPaired: snapshot.isPaired,
            musicInfo: nil,
            albumArtBase64: nil
        )

        // Update last sent snapshot
        lastSentSnapshot = snapshot

        // Handle N/A battery status for desktop Macs
        if batteryInfo.level == -1 {
            print("[mac-info-sync] Sent device status update (desktop Mac - no battery, no music)")
        } else {
            print("[mac-info-sync] Sent device status update (battery: \(batteryInfo.level)%, charging: \(batteryInfo.isCharging), no music)")
        }
    }

    private func sendDeviceStatusIfNeeded(with info: NowPlayingInfo) {
        // Only send if there's a connected device
        guard AppState.shared.device != nil else { return }

        // Check if now playing is enabled - if not, send status without music info
        let shouldIncludeMusicInfo = AppState.shared.sendNowPlayingStatus
        
        // Get battery info
        let batteryInfo = getBatteryInfo()

        var currentHash: String? = nil
        if let rawData = info.artworkData {
            let hashed = SHA256.hash(data: rawData)
            currentHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
        }

        let isArtworkChanged = (currentHash != lastSentArtworkHash)
        let artworkToSend: String?
        if shouldIncludeMusicInfo {
            if isArtworkChanged {
                if let rawData = info.artworkData {
                    artworkToSend = rawData.base64EncodedString()
                } else {
                    artworkToSend = ""
                }
                self.artworkBase64 = artworkToSend ?? ""
            } else {
                // If artwork hash hasn't changed, send current cached artworkBase64 so Android doesn't miss or clear it
                artworkToSend = self.artworkBase64
            }
        } else {
            artworkToSend = nil
        }

        // Build snapshot mirroring the payload we would send
        let musicSnapshot: Snapshot.Music? = {
            guard shouldIncludeMusicInfo else { return nil }
            return Snapshot.Music(
                isPlaying: info.isPlaying ?? false,
                title: info.title ?? "",
                artist: info.artist ?? "",
                volume: MacRemoteManager.shared.lastVolumeLevel,
                isMuted: MacRemoteManager.shared.lastVolumeLevel == 0,
                albumArt: currentHash ?? "", // Use hash for snapshot comparison
                likeStatus: "none", // must match payload default
                elapsedTime: Int(info.elapsedTime ?? 0),
                duration: Int(info.duration ?? 0)
            )
        }()

        let snapshot = Snapshot(
            batteryLevel: batteryInfo.level,
            isCharging: batteryInfo.isCharging,
            isPaired: true,
            music: musicSnapshot
        )

        // Early exit if nothing changed compared to the last sent payload
        guard snapshot != lastSentSnapshot else {
//            print("[mac-info-sync] No change, Skipping")
            return
        }

        // Send full device status
        WebSocketServer.shared.sendDeviceStatus(
            batteryLevel: snapshot.batteryLevel,
            isCharging: snapshot.isCharging,
            isPaired: snapshot.isPaired,
            musicInfo: shouldIncludeMusicInfo ? info : nil,
            albumArtBase64: artworkToSend
        )
        print("[mac-info-sync] Sent status \(snapshot.batteryLevel), \(snapshot.isCharging), \(info)")

        // Update last sent trackers
        lastSentSnapshot = snapshot
        if shouldIncludeMusicInfo { 
            lastSentInfo = info
            if let sent = artworkToSend {
                lastSentArtworkHash = sent.isEmpty ? nil : currentHash
            }
        }

        // Logging
//        if shouldIncludeMusicInfo {
//            print("Sent device status to Android: \(info.title ?? "Unknown") by \(info.artist ?? "Unknown")")
//        } else {
//            if batteryInfo.level == -1 {
//                print("Sent device status update (desktop Mac - no battery)")
//            } else {
//                print("Sent device status update (battery: \(batteryInfo.level)%, charging: \(batteryInfo.isCharging))")
//            }
//        }
    }

    private func getBatteryInfo() -> (level: Int, isCharging: Bool) {
        // Check if this is a MacBook (Air or Pro) - only these have batteries
        let deviceType = DeviceTypeUtil.deviceTypeDescription()
        let isMacBook = deviceType.contains("MacBook")
        
        guard isMacBook else {
            // For desktop Macs (iMac, Mac mini, Mac Pro, Mac Studio), return N/A status
            print("[mac-info-sync] Desktop Mac detected (\(deviceType)) - no battery present")
            return (level: -1, isCharging: false) // -1 indicates N/A
        }
        
        // Get battery info using pmset command for MacBooks
        if let batteryStatus = BatteryInfo.fetchStatus() {
            return (level: batteryStatus.percentage, isCharging: batteryStatus.isCharging)
        }
        
        // Fallback to hardcoded values if battery info can't be retrieved on MacBook
        print("[mac-info-sync] Failed to fetch battery status on MacBook, using fallback values")
        return (level: 75, isCharging: false)
    }

    // MARK: - Media Control Functions
    func togglePlayPause() {
        NowPlayingCLI.shared.toggle()
    }

    func play() {
        NowPlayingCLI.shared.play()
    }

    func pause() {
        NowPlayingCLI.shared.pause()
    }

    func next() {
        NowPlayingCLI.shared.next()
    }

    func previous() {
        NowPlayingCLI.shared.previous()
    }

    func stop() {
        NowPlayingCLI.shared.stop()
    }
}
