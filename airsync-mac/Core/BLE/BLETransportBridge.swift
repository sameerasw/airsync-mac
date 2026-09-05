import Foundation
import AppKit
import CoreBluetooth
import UserNotifications

class BLETransportBridge {
    static let shared = BLETransportBridge()
    
    func handleIncoming(uuid: CBUUID, payload: String) {
        let components = payload.components(separatedBy: BLEConstants.delimiter)
        
        switch uuid {
        case BLEConstants.charNotificationData:
            handleNotification(components)
        case BLEConstants.charMediaState:
            handleMediaState(components)
        case BLEConstants.charClipboardDataNotify:
            handleClipboard(payload)
        case BLEConstants.charDeviceName:
            handleDeviceName(payload)
        case BLEConstants.charNotificationDismissNotify:
            handleNotificationDismiss(payload)
        case BLEConstants.charMacControl:
            handleMacControl(payload)
        default:
            break
        }
    }
    
    private func handleMacControl(_ payload: String) {
        let components = payload.components(separatedBy: "|")
        guard components.count >= 2 else { return }
        let type = components[0]
        let action = components[1]
        let value = components.count >= 3 ? components[2] : nil
        
        DispatchQueue.main.async {
            switch type {
            case "media":
                WebSocketServer.shared.handleMediaControl(action: action)
            case "volume":
                if action == "vol_set", let value = value, let level = Int(value) {
                    MacRemoteManager.shared.setVolume(level)
                } else {
                    WebSocketServer.shared.handleVolumeControl(action: action)
                }
            case "remote":
                if action == "manual_disconnect" {
                    print("[BLE] Received manual disconnect from Android client! Instantly disconnecting...")
                    BLECentralManager.shared.disconnect()
                } else {
                    self.handleRemoteControl(action, value: value)
                }
            default:
                break
            }
        }
    }
    
    private func handleRemoteControl(_ action: String, value: String? = nil) {
        print("[ble] Received remote control: \(action)\(value.map { ", value: \($0)" } ?? "")")
        switch action {
        case "arrow_up": MacRemoteManager.shared.simulateKey(.upArrow)
        case "arrow_down": MacRemoteManager.shared.simulateKey(.downArrow)
        case "arrow_left": MacRemoteManager.shared.simulateKey(.leftArrow)
        case "arrow_right": MacRemoteManager.shared.simulateKey(.rightArrow)
        case "enter": MacRemoteManager.shared.simulateKey(.enter)
        case "space": MacRemoteManager.shared.simulateKey(.space)
        case "escape": MacRemoteManager.shared.simulateKey(.escape)
        case "lock_screen": MacRemoteManager.shared.lockScreen()
        case "screensaver": MacRemoteManager.shared.startScreensaver()
        case "brightness_up": MacRemoteManager.shared.increaseBrightness()
        case "brightness_down": MacRemoteManager.shared.decreaseBrightness()
        // Media: use NowPlayingCLI for reliability (HID simulation is unreliable from BLE context)
        case "media_play_pause": NowPlayingCLI.shared.toggle()
        case "media_next": NowPlayingCLI.shared.next()
        case "media_prev": NowPlayingCLI.shared.previous()
        case "vol_up": MacRemoteManager.shared.increaseVolume()
        case "vol_down": MacRemoteManager.shared.decreaseVolume()
        case "vol_mute": MacRemoteManager.shared.toggleMute()
        case "vol_set":
            if let value = value, let level = Int(value) {
                MacRemoteManager.shared.setVolume(level)
            }
        default: break
        }
    }
    
    private func handleNotification(_ components: [String]) {
        let pkg: String
        let appName: String
        let title: String
        let text: String
        
        if components.count >= 4 {
            pkg = components[0]
            appName = components[1]
            title = components[2]
            text = components[3]
        } else if components.count >= 3 {
            pkg = components[0]
            appName = pkg // Fallback to package name
            title = components[1]
            text = components[2]
        } else {
            return
        }
        
        let notif = Notification(
            title: title,
            body: text,
            app: appName,
            nid: UUID().uuidString,
            package: pkg,
            priority: "",
            actions: []
        )
        
        DispatchQueue.main.async {
            AppState.shared.addNotification(notif)
        }
    }
    
    private func handleMediaState(_ components: [String]) {
        guard components.count >= 6 else { return }
        let isPlaying = components[0] == "1"
        let title = components[1]
        let artist = components[2]
        let volume = Int(components[3]) ?? 0
        let isMuted = components[4] == "1"
        let likeStatus = components[5]
        
        // Update AppState.status
        DispatchQueue.main.async {
            let music = DeviceStatus.Music(
                isPlaying: isPlaying,
                title: title,
                artist: artist,
                volume: volume,
                isMuted: isMuted,
                albumArt: "", // No art over BLE
                likeStatus: likeStatus,
                duration: -1.0,
                position: -1.0,
                isBuffering: false
            )
            
            if AppState.shared.status == nil {
                AppState.shared.status = DeviceStatus(battery: DeviceStatus.Battery(level: 0, isCharging: false), isPaired: true, music: music)
            } else {
                AppState.shared.status?.music = music
            }
        }
    }
    
    private func handleClipboard(_ text: String) {
        print("[ble] Received clipboard update: \(text.prefix(20))...")
        DispatchQueue.main.async {
            // Update clipboard if sync enabled
            if AppState.shared.isClipboardSyncEnabled {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }
    
    private func handleDeviceName(_ name: String) {
        print("[ble] Received device name: \(name)")
        DispatchQueue.main.async {
            BLECentralManager.shared.connectedDeviceName = name
            if AppState.shared.device != nil {
                AppState.shared.device?.name = name
            }
        }
    }
    
    private func handleNotificationDismiss(_ id: String) {
        print("[ble] Received notification dismissal: \(id)")
        DispatchQueue.main.async {
            AppState.shared.removeNotificationById(id)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
    
    // --- Outbound ---
    
    func sendMediaControl(_ action: String) {
        BLECentralManager.shared.writeChunked(characteristicUUID: BLEConstants.charMediaControl, payload: action)
    }
    
    func sendMacMediaState(info: NowPlayingInfo) {
        let payload = [
            (info.isPlaying ?? false) ? "1" : "0",
            info.title ?? "",
            info.artist ?? "",
            String(MacRemoteManager.shared.lastVolumeLevel),
            (MacRemoteManager.shared.lastVolumeLevel == 0) ? "1" : "0",
            "none"
        ].joined(separator: BLEConstants.delimiter)
        
        BLECentralManager.shared.writeChunked(characteristicUUID: BLEConstants.charMacMediaState, payload: payload)
    }
    
    func sendClipboard(_ text: String) {
        BLECentralManager.shared.writeChunked(characteristicUUID: BLEConstants.charClipboardDataWrite, payload: text)
    }
}
