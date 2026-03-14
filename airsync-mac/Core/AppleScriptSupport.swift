//
//  AppleScriptSupport.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-10-01.
//

import Foundation
import Cocoa
import SwiftUI

// MARK: - AppleScript Commands

@objc(AirSyncDisconnectCommand)
class AirSyncDisconnectCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let appState = AppState.shared

        if let device = appState.device {
            let deviceName = device.name
            DispatchQueue.main.async {
                appState.disconnectDevice()
            }
            return "Disconnected from \(deviceName)"
        } else {
            return "Not connected"
        }
    }
}

@objc(AirSyncStatusCommand)
class AirSyncStatusCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let appState = AppState.shared

        if let device = appState.device {
            let statusInfo = [
                "device_name": device.name,
                "device_ip": device.ipAddress,
                "device_port": String(device.port),
                "device_version": device.version,
                "adb_connected": String(appState.adbConnected),
                "notifications_count": String(appState.notifications.count)
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: statusInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }

            return "Device: \(device.name) (\(device.ipAddress):\(device.port))"
        } else {
            return "No device connected"
        }
    }
}

@objc(AirSyncReconnectCommand)
class AirSyncReconnectCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if let lastDevice = QuickConnectManager.shared.getLastConnectedDevice() {
            DispatchQueue.main.async {
                QuickConnectManager.shared.wakeUpLastConnectedDevice()
            }
            return "Attempting to reconnect to \(lastDevice.name) (\(lastDevice.ipAddress))"
        } else {
            return "No previous device found for current network"
        }
    }
}

@objc(AirSyncGetNotificationsCommand)
class AirSyncGetNotificationsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let appState = AppState.shared

        if appState.device != nil {
            let notifications = Array(appState.notifications.prefix(20))

            if notifications.isEmpty {
                return "No notifications"
            }

            let notificationData = notifications.map { notif in
                var data: [String: Any] = [
                    "title": notif.title,
                    "body": notif.body,
                    "app": notif.app,
                    "id": notif.id.uuidString,
                    "package": notif.package,
                    "nid": notif.nid
                ]
                
                // Add available actions
                let actionData = notif.actions.map { action in
                    [
                        "name": action.name,
                        "type": action.type.rawValue
                    ]
                }
                data["actions"] = actionData

                // Add app icon as base64 if available
                if let iconPath = appState.androidApps[notif.package]?.iconUrl,
                   let iconData = NSData(contentsOfFile: iconPath) {
                    data["app_icon_base64"] = iconData.base64EncodedString()
                }

                return data
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: notificationData, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }

            return "Found \(notifications.count) notifications"
        } else {
            return "No device connected"
        }
    }
}

@objc(AirSyncGetMediaCommand)
class AirSyncGetMediaCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let appState = AppState.shared

        if let device = appState.device {
            if let music = appState.status?.music {
                var mediaInfo: [String: Any] = [
                    "title": music.title,
                    "artist": music.artist,
                    "is_playing": String(music.isPlaying),
                    "volume": String(music.volume),
                    "is_muted": String(music.isMuted),
                    "like_status": music.likeStatus
                ]

                // Add album art as base64 if available (albumArt is already base64)
                if !music.albumArt.isEmpty {
                    mediaInfo["album_art_base64"] = music.albumArt
                }

                if let jsonData = try? JSONSerialization.data(withJSONObject: mediaInfo, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }

                return "\(music.title) by \(music.artist) - \(music.isPlaying ? "Playing" : "Paused")"
            } else {
                return "No media playing on \(device.name)"
            }
        } else {
            return "No device connected"
        }
    }
}

@objc(AirSyncLaunchMirroringCommand)
class AirSyncLaunchMirroringCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            return "Requires AirSync+"
        }

        // Check if device is connected
        guard let device = AppState.shared.device else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "no_device_connected",
                "message": "No Android device connected. Please connect a device first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }

        // Check if ADB is available
        guard ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) != nil else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "adb_not_found",
                "message": "ADB not found. Please install via Homebrew: brew install android-platform-tools"
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "ADB not found"
        }

        // Check if scrcpy is available
        guard ADBConnector.findExecutable(named: "scrcpy", fallbackPaths: ADBConnector.possibleScrcpyPaths) != nil else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "scrcpy_not_found",
                "message": "scrcpy not found. Please install via Homebrew: brew install scrcpy"
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "scrcpy not found"
        }

        // Check if ADB is connected
        guard AppState.shared.adbConnected else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "adb_not_connected",
                "message": "ADB not connected. Please enable wireless debugging on your Android device and connect via ADB first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "ADB not connected"
        }

        // Start mirroring
        DispatchQueue.main.async {
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: AppState.shared.adbPort,
                deviceName: device.name
            )
        }

        let successInfo: [String: Any] = [
            "success": true,
            "message": "Launching mirroring for \(device.name)",
            "device": device.name,
            "ip": device.ipAddress
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: successInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Starting mirroring for \(device.name)"
    }
}

@objc(AirSyncGetAppsCommand)
class AirSyncGetAppsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            return "Requires AirSync+"
        }

        guard AppState.shared.device != nil else {
            return "No device connected"
        }

        // Check if ADB is connected
        guard AppState.shared.adbConnected else {
            return "ADB is not connected"
        }

        let apps = Array(AppState.shared.androidApps.values).sorted { $0.name.lowercased() < $1.name.lowercased() }

        var appsArray: [[String: Any]] = []

        for app in apps {
            var appIconBase64: String? = nil

            // Convert app icon to base64 if available
            if let iconPath = app.iconUrl,
               let imageData = NSImage(contentsOfFile: iconPath)?.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: imageData),
               let pngData = bitmapRep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                appIconBase64 = pngData.base64EncodedString()
            }

            let appInfo: [String: Any] = [
                "package_name": app.packageName,
                "name": app.name,
                "system_app": app.systemApp,
                "listening": app.listening,
                "icon": appIconBase64 ?? ""
            ]

            appsArray.append(appInfo)
        }

        let result: [String: Any] = [
            "apps": appsArray,
            "count": appsArray.count
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Failed to serialize apps information"
    }
}

@objc(AirSyncMirrorAppCommand)
class AirSyncMirrorAppCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            return "Requires AirSync+"
        }

        // Check if device is connected
        guard let device = AppState.shared.device else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "no_device_connected",
                "message": "No Android device connected. Please connect a device first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }

        // Check if ADB is connected
        guard AppState.shared.adbConnected else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "adb_not_connected",
                "message": "ADB not connected. Please enable wireless debugging and connect via ADB first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "ADB not connected"
        }

        // Get package name from command arguments
        guard let packageName = self.directParameter as? String, !packageName.isEmpty else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "missing_package_name",
                "message": "Package name is required. Usage: mirror app \"com.example.app\""
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Package name required"
        }

        // Check if app exists
        guard let app = AppState.shared.androidApps[packageName] else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "app_not_found",
                "message": "App with package name '\(packageName)' not found on device."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "App not found: \(packageName)"
        }

        // Start app-specific mirroring
        DispatchQueue.main.async {
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: AppState.shared.adbPort,
                deviceName: device.name,
                package: packageName
            )
        }

        let successInfo: [String: Any] = [
            "success": true,
            "message": "Launching app-specific mirroring for \(app.name)",
            "app_name": app.name,
            "package_name": packageName,
            "device": device.name
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: successInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Starting app mirroring for \(app.name)"
    }
}

@objc(AirSyncDesktopModeCommand)
class AirSyncDesktopModeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            return "Requires AirSync+"
        }

        // Check if device is connected
        guard let device = AppState.shared.device else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "no_device_connected",
                "message": "No Android device connected. Please connect a device first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }

        // Check if ADB is connected
        guard AppState.shared.adbConnected else {
            let errorInfo: [String: Any] = [
                "success": false,
                "error": "adb_not_connected",
                "message": "ADB not connected. Please enable wireless debugging and connect via ADB first."
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "ADB not connected"
        }

        // Start desktop mode mirroring
        DispatchQueue.main.async {
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: AppState.shared.adbPort,
                deviceName: device.name,
                desktop: true
            )
        }

        let successInfo: [String: Any] = [
            "success": true,
            "message": "Launching desktop mode mirroring for \(device.name)",
            "device": device.name,
            "mode": "desktop",
            "note": "Desktop mode requires Android 15+ and vendor support"
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: successInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Starting desktop mode mirroring for \(device.name)"
    }
}

@objc(AirSyncConnectADBCommand)
class AirSyncConnectADBCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            return "Requires AirSync+"
        }

        // Check if device is connected
        guard let device = AppState.shared.device else {
            return "No device connected"
        }

        // Check if already connecting
        guard !AppState.shared.adbConnecting else {
            return "ADB connection already in progress"
        }

        // Check if already connected
        if AppState.shared.adbConnected {
            return "Connected"
        }

        // ADB is supported only on direct LAN sessions, not relay mode.
        guard WebSocketServer.shared.hasActiveLocalSession() else {
            return "ADB works only on local LAN connections. Relay mode is not supported for ADB."
        }

        // Start ADB connection (like the Connect ADB button in settings)
        DispatchQueue.main.async {
            ADBConnector.connectToADB(ip: device.ipAddress)
        }

        // Wait a moment for the connection attempt to complete
        let semaphore = DispatchSemaphore(value: 0)
        var result = "Connecting..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if AppState.shared.adbConnected {
                result = "Connected"
            } else if let errorResult = AppState.shared.adbConnectionResult {
                // Parse common error messages
                let lowercased = errorResult.lowercased()
                if lowercased.contains("not found") {
                    result = "ADB not found. Please install via Homebrew: brew install android-platform-tools"
                } else if lowercased.contains("no results") || lowercased.contains("mdns") {
                    result = "Device not found. Make sure wireless debugging is enabled and device is on same network"
                } else if lowercased.contains("protocol fault") || lowercased.contains("connection reset") {
                    result = "ADB connection failed. Another ADB instance may be using the device"
                } else if lowercased.contains("refused") {
                    result = "Connection refused. Check if wireless debugging is enabled"
                } else {
                    result = "Connection failed. Check ADB console in settings for details"
                }
            } else {
                result = "Connection failed"
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
}

@objc(AirSyncMediaControlCommand)
class AirSyncMediaControlCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let action = self.directParameter as? String else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Missing action parameter. Available actions: play, pause, toggle, next, previous, like, unlike, toggle_like"
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Error: Missing action parameter"
        }

        // Check if user has Plus subscription
        guard AppState.shared.isPlus else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Media control requires AirSync Plus subscription",
                "requires_plus": true
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Media control requires AirSync+"
        }

        let appState = AppState.shared

        guard appState.device != nil else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "No device connected"
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }

        let webSocketServer = WebSocketServer.shared
        var resultInfo: [String: Any] = [:]

        // Store the current media state before the command
        let previousMusicState = appState.status?.music

        switch action.lowercased() {
        case "play":
            webSocketServer.togglePlayPause()
            resultInfo = [
                "status": "success",
                "action": "play",
                "message": "Play command sent"
            ]

        case "pause":
            webSocketServer.togglePlayPause()
            resultInfo = [
                "status": "success",
                "action": "pause",
                "message": "Pause command sent"
            ]

        case "toggle", "toggle_play_pause", "playpause":
            webSocketServer.togglePlayPause()
            resultInfo = [
                "status": "success",
                "action": "toggle_play_pause",
                "message": "Toggle play/pause command sent"
            ]

        case "next", "skip_next":
            webSocketServer.skipNext()
            resultInfo = [
                "status": "success",
                "action": "next",
                "message": "Next track command sent"
            ]

        case "previous", "skip_previous", "prev":
            webSocketServer.skipPrevious()
            resultInfo = [
                "status": "success",
                "action": "previous",
                "message": "Previous track command sent"
            ]

        case "like":
            webSocketServer.like()
            resultInfo = [
                "status": "success",
                "action": "like",
                "message": "Like command sent"
            ]

        case "unlike":
            webSocketServer.unlike()
            resultInfo = [
                "status": "success",
                "action": "unlike",
                "message": "Unlike command sent"
            ]

        case "toggle_like":
            webSocketServer.toggleLike()
            resultInfo = [
                "status": "success",
                "action": "toggle_like",
                "message": "Toggle like command sent"
            ]

        default:
            resultInfo = [
                "status": "error",
                "message": "Invalid action: \(action). Available actions: play, pause, toggle, next, previous, like, unlike, toggle_like"
            ]
        }

        // Wait for updated media information (only for successful commands)
        if resultInfo["status"] as? String == "success" {
            // Give some time for the command to execute and update the state
            let semaphore = DispatchSemaphore(value: 0)
            var attempts = 0
            let maxAttempts = 20 // 2 seconds total (20 * 100ms)

            DispatchQueue.global(qos: .userInitiated).async {
                while attempts < maxAttempts {
                    usleep(250_000) // Wait 100ms
                    attempts += 1

                    // Check if media state has been updated
                    DispatchQueue.main.sync {
                        let currentMusic = appState.status?.music

                        // For track changes (next/previous), wait for title/artist change
                        if ["next", "skip_next", "previous", "skip_previous", "prev"].contains(action.lowercased()) {
                            if let prev = previousMusicState, let current = currentMusic {
                                if prev.title != current.title || prev.artist != current.artist {
                                    semaphore.signal()
                                    return
                                }
                            }
                        }
                        // For play/pause, wait for isPlaying state change
                        else if ["play", "pause", "toggle", "toggle_play_pause", "playpause"].contains(action.lowercased()) {
                            if let prev = previousMusicState, let current = currentMusic {
                                if prev.isPlaying != current.isPlaying {
                                    semaphore.signal()
                                    return
                                }
                            }
                        }
                        // For like actions, wait for like status change
                        else if ["like", "unlike", "toggle_like"].contains(action.lowercased()) {
                            if let prev = previousMusicState, let current = currentMusic {
                                if prev.likeStatus != current.likeStatus {
                                    semaphore.signal()
                                    return
                                }
                            }
                        }
                    }
                }
                // Timeout reached
                semaphore.signal()
            }

            // Wait for either state change or timeout
            _ = semaphore.wait(timeout: .now() + 1.5) // 2.5 second maximum wait
        }

        // Add current media status if available (now with updated info)
        if let music = appState.status?.music {
            resultInfo["current_media"] = [
                "title": music.title,
                "artist": music.artist,
                "is_playing": music.isPlaying,
                "like_status": music.likeStatus
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: resultInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "Media control action completed"
    }
}

@objc(AirSyncNotificationActionCommand)
class AirSyncNotificationActionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Expecting format: "notification_id|action_name" or "notification_id|action_name|reply_text"
        guard let parameter = self.directParameter as? String else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Missing parameter. Format: 'notification_id|action_name' or 'notification_id|action_name|reply_text'"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Error: Missing parameter"
        }
        
        let components = parameter.components(separatedBy: "|")
        guard components.count >= 2 else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Invalid parameter format. Use: 'notification_id|action_name' or 'notification_id|action_name|reply_text'"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Error: Invalid parameter format"
        }
        
        let notificationId = components[0]
        let actionName = components[1]
        let replyText = components.count > 2 ? components[2] : nil
        
        let appState = AppState.shared
        
        guard appState.device != nil else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "No device connected"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }
        
        // Find the notification by ID
        guard let notification = appState.notifications.first(where: { $0.id.uuidString == notificationId }) else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Notification not found with ID: \(notificationId)"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Notification not found"
        }
        
        // Verify the action exists
        guard notification.actions.contains(where: { $0.name == actionName }) else {
            let availableActions = notification.actions.map { $0.name }.joined(separator: ", ")
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Action '\(actionName)' not available. Available actions: \(availableActions)"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Action not available"
        }
        
        // Send the notification action
        WebSocketServer.shared.sendNotificationAction(id: notification.nid, name: actionName, text: replyText)
        
        let resultInfo: [String: Any] = [
            "status": "success",
            "message": "Notification action sent",
            "notification_id": notificationId,
            "action_name": actionName,
            "reply_text": replyText ?? "",
            "notification_title": notification.title
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: resultInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Notification action sent"
    }
}

@objc(AirSyncDismissNotificationCommand)
class AirSyncDismissNotificationCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let notificationId = self.directParameter as? String else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Missing notification ID parameter"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Error: Missing notification ID"
        }
        
        let appState = AppState.shared
        
        guard appState.device != nil else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "No device connected"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "No device connected"
        }
        
        // Find the notification by ID
        guard let notification = appState.notifications.first(where: { $0.id.uuidString == notificationId }) else {
            let errorInfo: [String: Any] = [
                "status": "error",
                "message": "Notification not found with ID: \(notificationId)"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorInfo, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "Notification not found"
        }
        
        // Dismiss the notification
        WebSocketServer.shared.dismissNotification(id: notification.nid)
        
        let resultInfo: [String: Any] = [
            "status": "success",
            "message": "Notification dismissed",
            "notification_id": notificationId,
            "notification_title": notification.title
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: resultInfo, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Notification dismissed"
    }
}