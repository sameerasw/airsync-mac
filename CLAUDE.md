# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AirSync is a macOS application that enables wireless communication between Mac and Android devices. It supports notification mirroring, media control, clipboard sync, file transfers, and screen mirroring via scrcpy integration. The app uses a WebSocket-based protocol with AES-256-GCM encryption for secure communication.

**Technology Stack:**
- Swift/SwiftUI for the macOS app
- WebSocket server (Swifter library) for real-time bidirectional communication
- CryptoKit for AES-256-GCM encryption
- Sparkle for auto-updates
- scrcpy and adb for Android screen mirroring

**Licensing Model:**
- Open source (MPL 2.0 with Non-Commercial Use Clause)
- Free tier with basic features
- Plus tier (premium) unlocks advanced features
- Trial system for Plus features
- Self-compiled builds automatically have Plus features enabled (via `SELF_COMPILED` flag)

## Build Commands

### Building the App

**In Xcode:**
1. Open `AirSync.xcodeproj`
2. Select the `AirSync Self Compiled` scheme (for self-compiled builds with Plus features)
3. Product → Archive
4. In the Organizer window: Distribute → Custom → Copy App
5. The built `AirSync.app` will be in the selected output folder

**Build Schemes:**
- `AirSync Self Compiled`: Builds with `SELF_COMPILED` flag, enabling all Plus features automatically
- Regular scheme: Standard build with licensing checks enabled

### Testing

There are no automated tests in this repository. Testing is done manually:
- Run the app and connect an Android device
- Test notification mirroring, media control, clipboard sync, file transfers
- Verify scrcpy integration if adb is installed

### Dependencies

External dependencies are managed via Swift Package Manager and included in the Xcode project:
- **Swifter**: HTTP/WebSocket server
- **Sparkle**: Auto-update framework
- **QRCode**: QR code generation (dagronf/QRCode)
- **LottieUI**: Lottie animations

No separate dependency installation step is required - Xcode handles SPM dependencies automatically.

## Architecture

### Core Components

**AppState (Core/AppState.swift)**
- Central state manager using `ObservableObject`
- Singleton pattern: `AppState.shared`
- Manages device connections, notifications, clipboard sync, file transfers, license status
- Persists settings to UserDefaults (device name, port, clipboard sync, window opacity, etc.)
- Coordinates with WebSocketServer for communication

**WebSocketServer (Core/WebSocket/WebSocketServer.swift)**
- Singleton WebSocket server: `WebSocketServer.shared`
- Listens on configurable port (default 5297)
- Handles message encryption/decryption with AES-256-GCM
- Routes incoming messages to handlers based on `MessageType`
- Manages active WebSocket sessions with Android devices
- Network monitoring: detects IP changes and restarts server automatically
- File transfer implementation with chunked upload/download and checksum verification

**Message Protocol (Model/Message.swift)**
- All WebSocket communication uses JSON messages with `type` and `data` fields
- Message types defined in `MessageType` enum: device, macInfo, notification, status, mediaControl, clipboardUpdate, fileTransfer*, etc.
- Messages are encrypted with AES-256-GCM when encryption is enabled
- Full protocol specification is documented in `DOCUMENTATION.md`

### Key Subsystems

**Encryption (Core/Util/Crypto/CryptoUtil.swift)**
- AES-256-GCM symmetric encryption for all WebSocket messages
- Key is generated on first launch and stored in UserDefaults (Base64-encoded)
- Functions: `generateSymmetricKey()`, `encryptMessage()`, `decryptMessage()`
- Same symmetric key is shared with Android app (via QR code or Quick Connect)

**File Transfers (Core/Util/FileTransfer/)**
- Chunked bidirectional file transfer protocol
- 64 KB default chunk size with sliding window acknowledgments (up to 8 chunks in-flight)
- SHA256 checksum verification for integrity
- Transfer state tracked in AppState.transfers dictionary
- Incoming files saved to Downloads folder
- FileTransferProtocol helper builds JSON messages for init/chunk/ack/complete

**ADB Integration (Core/Util/CLI/ADBConnector.swift)**
- Connects to Android device via adb (wireless debugging)
- Launches scrcpy for full-device or per-app mirroring (Plus feature)
- Configurable bitrate and resolution for scrcpy
- Automatic connection when device pairs (if ADB enabled and Plus active)

**Trial & Licensing (Core/Trial/)**
- TrialManager: Handles trial activation and expiration
- Trial stored in keychain using TrialSecretProvider for security
- Gumroad.swift: License validation with Gumroad API
- License details cached in UserDefaults
- `#if SELF_COMPILED` bypasses licensing and enables all Plus features

**Quick Connect (Core/QuickConnect/QuickConnectManager.swift)**
- Stores last connected device (IP, port, name)
- Sends wake-up request to reconnect to previously paired device
- Uses WebSocket wakeUpRequest message type

**App Icons (Core/Util/AppIcons/)**
- AppIconManager: Manages alternate app icons (Plus feature)
- Icons defined in AppIconExtensions.swift with allIcons array
- Icon assets stored in Assets.xcassets/AppIcons/
- Reverts to default icon if Plus subscription expires

**Localization (Localization/)**
- Localizer.swift: Centralized string localization
- Multiple languages supported (crowdin integration)
- String files in Localization/ directory

### UI Structure (Screens/)

**HomeView**: Main window with tabs
- SidebarView: Tab navigation (QR code, Notifications, Apps, Phone, Transfers, Settings)
- PhoneView: Device status card showing battery, music player, time, wallpaper
- NotificationView: List of Android notifications with action buttons
- AppsView: Grid of Android apps with notification toggle switches and pin functionality
- TransfersView: File transfer progress tracking
- SettingsView: App settings, license activation, features toggles

**MenubarView**: Menu bar extra (status bar app)
- Shows connected device name and notification count
- Quick access to recent notifications
- Displays battery level and music info

**OnboardingView**: First-run wizard
- Welcome screen
- Android app installation instructions
- Mirroring setup (scrcpy/adb)
- Plus features promotion

**ScannerView**: QR code display for pairing
- Shows QR code with connection info (IP, port, encryption key)
- Auto-refreshes when network changes

### Data Models (Model/)

- **Device**: Represents Mac or Android device (name, IP, port, version)
- **Notification**: Android notification with actions (reply, dismiss)
- **DeviceStatus**: Battery, music playback info, pairing status
- **AndroidApp**: App metadata (package name, icon URL, notification enabled state)
- **NowPlayingInfo**: Mac media playback info (title, artist, album art)
- **MacInfo**: Mac device info sent to Android on connection
- **FileTransferSession**: Transfer state (progress, size, checksum)
- **PinnedApp**: Pinned app for quick access (up to 3 apps)

## Communication Flow

1. **Connection Handshake:**
   - Mac starts WebSocketServer on port (default 5297)
   - Android scans QR code to get IP, port, encryption key
   - Android connects to ws://MAC_IP:PORT/socket
   - Android sends `device` message with device info
   - Mac responds with `macInfo` message (device name, Plus status, saved app packages)
   - Mac sends `appIcons` request if app lists don't match

2. **Ongoing Communication:**
   - Android sends `notification` messages for new notifications
   - Android sends `status` messages with battery/music updates (periodic)
   - Mac sends `mediaControl` messages to control Android playback
   - Mac sends `volumeControl` messages to adjust Android volume
   - Android sends `macMediaControl` messages to control Mac playback
   - Bidirectional `clipboardUpdate` messages for clipboard sync
   - File transfers use `fileTransferInit` → `fileChunk` → `fileChunkAck` → `fileTransferComplete` → `transferVerified`

3. **Disconnection:**
   - Mac can send `disconnectRequest` to Android
   - WebSocket disconnect triggers AppState.disconnectDevice()
   - Clears device, notifications, status, transfers

## Settings & UserDefaults Keys

Key settings persisted in UserDefaults:
- `deviceName`: Mac device name
- `devicePort`: WebSocket server port (default 5297)
- `adbPort`: ADB wireless debugging port (default 5555)
- `adbEnabled`: Whether ADB auto-connect is enabled
- `mirroringPlus`: Whether to show "View" button in notifications (Plus feature)
- `isClipboardSyncEnabled`: Clipboard sync toggle
- `sendNowPlayingStatus`: Send Mac media info to Android
- `windowOpacity`: Main window opacity
- `hideDockIcon`: Hide dock icon (menu bar only mode)
- `showMenubarText`: Show text in menu bar
- `showMenubarDeviceName`: Show device name in menu bar
- `menubarTextMaxLength`: Max characters for menu bar text
- `notificationSound`: Notification sound choice
- `dismissNotif`: Auto-dismiss notifications on Android when dismissed on Mac
- `scrcpyBitrate`: scrcpy video bitrate (Mbps)
- `scrcpyResolution`: scrcpy max resolution
- `selectedNetworkAdapterName`: Network adapter for server (nil = auto)
- `encryptionKey`: AES-256-GCM symmetric key (Base64)
- `isPlus`: Plus license status
- `licenseDetails`: Cached license info (JSON)
- `hasPairedDeviceOnce`: First pairing flag
- `pinnedApps`: Pinned apps (JSON array)
- `isMusicCardHidden`: Hide music card on PhoneView

## Important Implementation Notes

**Plus Features:**
- Screen mirroring (scrcpy integration)
- Custom app icons
- Advanced settings (window opacity, dock icon hiding, etc.)
- Plus features are checked via `AppState.shared.isPlus`
- Self-compiled builds bypass licensing with `#if SELF_COMPILED`

**Network Adapter Selection:**
- Auto mode: Prioritizes en* adapters, then private IPs (192.168.*, 10.*, 172.16-31.*)
- Manual mode: User can select specific adapter in settings
- Network monitoring detects IP changes and refreshes QR code / restarts server
- Validation ensures selected adapter has valid IP before using it

**Encryption:**
- Encryption key is generated once and reused for all connections
- Key is shown in QR code for Android to decrypt messages
- Messages are Base64-encoded after AES-GCM encryption
- If decryption fails, server logs error but doesn't disconnect (allows unencrypted fallback)

**File Transfers:**
- Sliding window protocol: 8 chunks in-flight, sender waits for acks before sending more
- Retry logic: up to 3 attempts per chunk if ack not received within 2 seconds
- Progress tracked in AppState.transfers dictionary (UI binds to this)
- Incoming files saved to ~/Downloads with original filename
- Checksum verification optional but recommended

**Notification Actions:**
- Android notifications can have reply and button actions
- Mac generates UNNotificationCategory dynamically for each notification
- User actions trigger `notificationAction` message to Android
- Android responds with `notificationActionResponse` (success/failure)

**AppleScript Support (Core/AppleScriptSupport.swift):**
- AirSync exposes AppleScript commands defined in AirSync.sdef
- Commands include: send notification, control media, get device status
- Allows automation and integration with other macOS apps

**Localization:**
- Localizer.swift provides centralized string localization
- Crowdin integration for community translations
- String keys follow pattern: `"key".localized()`

## Common Development Workflows

**Adding a New Message Type:**
1. Add case to `MessageType` enum in Model/Message.swift
2. Add handler in `WebSocketServer.handleMessage()` switch statement
3. Create sender function in WebSocketServer if needed (e.g., `sendMediaAction()`)
4. Update DOCUMENTATION.md with new message format

**Adding a New App Icon:**
1. Add image assets to Assets.xcassets/AppIcons/ (.imageset and optional .appiconset)
2. Define icon in AppIconExtensions.swift: `static let newIcon = AppIcon(...)`
3. Add to `allIcons` array in AppIconExtensions.swift
4. Icon will appear in Settings → App Icon picker (Plus feature)

**Adding a New Setting:**
1. Add @Published property to AppState with didSet to persist to UserDefaults
2. Add UI control in SettingsView or SettingsFeaturesView
3. Read initial value in AppState.init() from UserDefaults with fallback

**Testing Protocol Changes:**
1. Use `wscat` or similar WebSocket client to connect to ws://localhost:5297/socket
2. Send test messages (JSON format) to verify server handling
3. Check console logs (print statements) for message processing
4. Test with actual Android app for full integration

## Dependencies on External Tools

**Optional (for full functionality):**
- **scrcpy**: Screen mirroring (Plus feature) - Install via Homebrew: `brew install scrcpy`
- **adb**: Android Debug Bridge for wireless connection - Install via Homebrew: `brew install android-platform-tools`
- **media-control**: Mac media control CLI (for NowPlayingCLI) - Install via Homebrew: `brew install media-control`

The app will function without these tools but with reduced functionality (no mirroring, no Mac media info sent to Android).

## Related Files

- **README.md**: User-facing documentation, build instructions, requirements
- **DOCUMENTATION.md**: Complete WebSocket protocol specification with message examples
- **CONTRIBUTING.md**: Contribution guidelines, licensing info, icon addition process
- **LICENSE**: MPL 2.0 + Non-Commercial Use Clause
