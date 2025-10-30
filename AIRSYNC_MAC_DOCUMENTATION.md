# AirSync Mac - Complete Documentation

**Last Updated:** October 30, 2025  
**Version:** 2.1.4

## Table of Contents
1. [Overview](#overview)
2. [Recent Fixes & Updates](#recent-fixes--updates)
3. [Features](#features)
4. [Known Issues](#known-issues)
5. [Architecture](#architecture)
6. [Development Notes](#development-notes)

---

## Overview

AirSync Mac is a macOS companion app for AirSync Android that enables seamless device integration including:
- Real-time notifications sync
- SMS/MMS messaging
- Call logs and live call notifications
- Health data monitoring
- File transfers
- Screen mirroring
- Media control
- Clipboard sync

---

## Recent Fixes & Updates

### Music Controls (Oct 30, 2025)
**Status:** ✅ Mac-side complete, ⚠️ Android needs update

**What was fixed:**
- Added `macMediaControl` message type for controlling Android media
- Music control buttons now always visible (play/pause, next, previous, like/unlike)
- Functionality gated by Plus license (shows upgrade prompt for free users)
- Added debug logging for media control actions

**What needs Android update:**
- Android must handle `macMediaControl` messages
- Android must execute media actions (play/pause, next, previous, like/unlike)
- Android must send `macMediaControlResponse` back to Mac

**Message format:**
```json
{
  "type": "macMediaControl",
  "data": {
    "action": "playPause" | "next" | "previous" | "like" | "unlike"
  }
}
```

### File Transfer Support (Oct 30, 2025)
**Status:** ✅ Complete

**What was fixed:**
- Updated to support new Android file transfer format
- Now handles both `transferId`/`id` field names
- Now handles both `data`/`chunk` field names for file chunks
- Automatically saves files to Downloads folder
- Shows macOS notification when file received
- Sends `transferVerified` response back to Android
- Proper SHA256 checksum verification

**Supported formats:**
- Old format: `id`, `name`, `size`, `mime`, `chunk`
- New format: `transferId`, `fileName`, `fileSize`, `totalChunks`, `data`

### Connection & Sync Issues (Oct 30, 2025)
**Status:** ✅ Fixed

**What was fixed:**
- Fixed WebSocket message encryption/decryption
- Fixed device reconnection after sleep/network change
- Fixed auto-sync of call logs, SMS, and health data on connection
- Improved network adapter selection
- Added quick-connect wake-up functionality

---

## Features

### ✅ Working Features

#### Notifications
- Real-time notification sync from Android
- Notification actions (reply, dismiss, etc.)
- System notification integration
- Notification history

#### Messaging (SMS/MMS)
- View SMS threads
- Read messages
- Send SMS (Plus feature)
- Mark as read
- Contact name resolution

#### Call Logs
- View call history
- Call duration and timestamps
- Contact name resolution
- Mark as read

#### Live Call Notifications
- Incoming/outgoing call alerts
- Caller ID display
- Call state tracking (ringing, active, ended)

#### Health Data
- Daily health summary
- Steps, distance, calories
- Heart rate (avg, min, max)
- Sleep duration
- Date picker for historical data
- Auto-refresh on date change

#### File Transfer
- Android → Mac: ✅ Working
- Mac → Android: ✅ Working
- Checksum verification (SHA256)
- Progress tracking
- Automatic save to Downloads

#### Screen Mirroring
- WebSocket-based mirroring (no ADB required)
- H.264 hardware decoding (VideoToolbox)
- Touch input support
- Keyboard input support
- Navigation controls

#### Media Control
- Display current playing track
- Album art display
- Volume control (Plus feature)
- Play/pause, next, previous buttons visible
- Like/unlike support (when available)
- ⚠️ Control functionality requires Android update

#### Clipboard Sync
- Bidirectional clipboard sync
- Automatic sync when enabled
- Manual copy/paste support

### ⚠️ Partially Working

#### Music Controls
- **Mac side:** ✅ Complete - sends `macMediaControl` messages
- **Android side:** ❌ Needs update - must handle messages and execute actions

---

## Known Issues

### 1. Music Controls Not Responding
**Issue:** Clicking music control buttons doesn't control Android media  
**Cause:** Android app doesn't handle `macMediaControl` messages  
**Status:** Mac-side complete, Android needs update  
**Workaround:** None - requires Android app update

### 2. SwiftUI Layout Warnings
**Issue:** Console shows layout constraint warnings  
**Cause:** SwiftUI auto-layout calculations  
**Status:** Cosmetic only, no functional impact  
**Workaround:** Can be ignored

---

## Architecture

### Core Components

#### WebSocketServer
- Handles all WebSocket communication
- Message encryption/decryption
- Connection management
- File transfer coordination
- Screen mirroring frame handling

#### AppState
- Central state management
- Published properties for UI updates
- Device connection state
- Notification storage
- SMS/Call log storage
- Health data storage
- File transfer tracking

#### LiveActivitiesManager
- Manages live notifications
- Call notification handling
- Health data updates
- Notification scheduling

#### H264Decoder
- Hardware-accelerated video decoding
- VideoToolbox integration
- Frame buffer management
- Fallback to software decoding if needed

### Message Types

#### Device & Connection
- `device` - Device info exchange
- `macInfo` - Mac system info
- `status` - Battery, music, pairing status
- `wakeUpRequest` - Wake device from sleep

#### Notifications
- `notification` - New notification
- `notificationAction` - Action button pressed
- `notificationActionResponse` - Action result
- `notificationUpdate` - Notification dismissed/updated
- `dismissalResponse` - Dismissal confirmation

#### Media Control
- `macMediaControl` - Mac controls Android media
- `macMediaControlResponse` - Android confirms action
- `mediaControlResponse` - Generic media response

#### Messaging
- `requestSmsThreads` - Request SMS list
- `smsThreads` - SMS thread data
- `requestSmsMessages` - Request messages for thread
- `smsMessages` - Message data
- `sendSms` - Send new SMS
- `smsSendResponse` - Send confirmation
- `smsReceived` - New SMS notification
- `markSmsRead` - Mark thread as read

#### Call Logs
- `requestCallLogs` - Request call history
- `callLogs` - Call log data
- `markCallLogRead` - Mark call as read
- `callNotification` - Live call alert
- `callAction` - Call action (answer/reject)
- `callActionResponse` - Action confirmation

#### Health Data
- `requestHealthSummary` - Request health data
- `healthSummary` - Daily health summary
- `requestHealthData` - Request detailed data
- `healthData` - Detailed health records

#### File Transfer
- `fileTransferInit` - Start file transfer
- `fileChunk` - File data chunk
- `fileTransferComplete` - Transfer finished
- `fileChunkAck` - Chunk received confirmation
- `transferVerified` - Checksum verification result

#### Screen Mirroring
- `mirrorRequest` - Request mirror session
- `mirrorResponse` - Mirror session response
- `mirrorStart` - Start mirroring
- `mirrorStop` - Stop mirroring
- `mirrorFrame` - H.264 video frame
- `inputEvent` - Touch/mouse input
- `navAction` - Navigation button
- `launchApp` - Launch Android app
- `screenshotRequest` - Request screenshot
- `screenshotResponse` - Screenshot data

#### Other
- `clipboardUpdate` - Clipboard content sync
- `appIcons` - Android app icons
- `wallpaperResponse` - Device wallpaper

---

## Development Notes

### Building
- Xcode 15.0+
- macOS 14.0+ deployment target
- Swift 5.9+

### Dependencies
- Swifter (WebSocket server)
- CryptoKit (encryption)
- VideoToolbox (H.264 decoding)

### Testing
- Test with Android app version 2.1.4+
- Ensure both devices on same network
- Check firewall settings (port 6996)

### Debugging
- Enable verbose logging in WebSocketServer
- Check console for `[websocket]` prefixed logs
- Monitor network traffic on port 6996

### Code Style
- Use SwiftUI for UI
- Follow Apple's Swift style guide
- Document public APIs
- Use meaningful variable names

---

## Quick Reference

### Common Tasks

**Check connection status:**
```swift
AppState.shared.device // nil if disconnected
AppState.shared.webSocketStatus // .started, .stopped, .failed
```

**Send message to Android:**
```swift
WebSocketServer.shared.sendToFirstAvailable(message: jsonString)
```

**Request data from Android:**
```swift
WebSocketServer.shared.requestSmsThreads()
WebSocketServer.shared.requestCallLogs()
WebSocketServer.shared.requestHealthSummary()
```

**Control Android media:**
```swift
WebSocketServer.shared.togglePlayPause()
WebSocketServer.shared.skipNext()
WebSocketServer.shared.skipPrevious()
```

**Send file to Android:**
```swift
WebSocketServer.shared.sendFile(url: fileURL)
```

---

## Support

For issues or questions:
1. Check this documentation
2. Review console logs
3. Verify Android app version compatibility
4. Check network connectivity
5. Restart both apps if needed

---

**End of Documentation**
