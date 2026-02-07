//
//  NowPlayingViewModel.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-17.
//
import Foundation
internal import Combine
import CryptoKit

class MacInfoSyncManager: ObservableObject {
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
        }
        let batteryLevel: Int
        let isCharging: Bool
        let isPaired: Bool
        let music: Music?
    }
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Monitor device connection status and start/stop polling accordingly
        AppState.shared.$device
            .sink { [weak self] device in
                if device != nil {
                    self?.startPolling()
                } else {
                    self?.stopPolling()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        stopPolling()
        cancellables.removeAll()
    }

    private func startPolling() {
        // Don't start if already running
        guard timer == nil else { return }

        print("[mac-info-sync] Starting device status monitoring - device connected")
        fetch() // initial fetch
        timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopPolling() {
        guard timer != nil else { return }

        print("[mac-info-sync] Stopping media playback monitoring - device disconnected")
        timer?.invalidate()
        timer = nil

        // Reset published properties when stopping
        title = "Unknown Title"
        artist = "Unknown Artist"
        album = "Unknown Album"
        elapsed = 0
        duration = 0
        isPlaying = false
        artworkBase64 = ""
        lastSentInfo = nil
        lastSentSnapshot = nil
        lastSentArtworkHash = nil
    }

    private func fetch() {
        // Only fetch if there's a connected device
        guard AppState.shared.device != nil else { return }

        // Check if now playing status is enabled
        if AppState.shared.sendNowPlayingStatus {
            // Fetch now playing info and send device status with music info
            NowPlayingCLI.shared.fetchNowPlaying { [weak self] info in
                guard let info = info else {
//                    print("[mac-info-sync] No now playing info")
                    // Still send device status without music info
                    self?.sendDeviceStatusWithoutMusic()
                    return
                }
                // MUST update @Published properties on main thread
                DispatchQueue.main.async {
//                    print("Now Playing fetched:", info) // debug
                    self?.title = info.title ?? "Unknown Title"
                    self?.artist = info.artist ?? "Unknown Artist"
                    self?.album = info.album ?? "Unknown Album"
                    self?.elapsed = info.elapsedTime ?? 0
                    self?.duration = info.duration ?? 0
                    self?.isPlaying = info.isPlaying ?? false

                    // Convert artwork to base64 if available
                    if let artworkData = info.artworkData {
                        self?.artworkBase64 = artworkData.base64EncodedString()
                    } else {
                        self?.artworkBase64 = ""
                    }

                    // Send to Android if connected and info has changed
                    self?.sendDeviceStatusIfNeeded(with: info)
                }
            }
        } else {
            // Now playing disabled - just send device status without music info
            sendDeviceStatusWithoutMusic()
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

        let currentArtwork = artworkBase64
        var currentHash: String? = nil
        
        if !currentArtwork.isEmpty {
            let inputData = Data(currentArtwork.utf8)
            let hashed = SHA256.hash(data: inputData)
            currentHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
        }

        let artworkToSend: String?
        if shouldIncludeMusicInfo {
            if currentHash != lastSentArtworkHash {
                artworkToSend = currentArtwork.isEmpty ? "" : currentArtwork
            } else {
                
                artworkToSend = nil
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
                volume: 50, // must match payload default
                isMuted: false, // must match payload default
                albumArt: currentHash ?? "", // Use hash for snapshot comparison
                likeStatus: "none" // must match payload default
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
