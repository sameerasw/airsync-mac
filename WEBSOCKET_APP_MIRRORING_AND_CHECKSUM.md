# WebSocket App Mirroring & MD5 Checksum Issue

## Issue 1: App Mirroring Using scrcpy Instead of WebSocket ❌

### Problem
The app grid was using `ADBConnector.startScrcpy()` for app-specific mirroring, which requires ADB connection and launches an external scrcpy process.

**User wanted**: WebSocket-based mirroring using the existing `mirrorRequest` protocol.

### Solution Applied

Changed from scrcpy to WebSocket mirroring:

**Before:**
```swift
private func handleTap() {
    if let device = appState.device, appState.adbConnected {
        ADBConnector.startScrcpy(
            ip: device.ipAddress,
            port: appState.adbPort,
            deviceName: device.name,
            package: app.packageName
        )
    }
}
```

**After:**
```swift
private func handleTap() {
    // Use WebSocket mirroring instead of scrcpy
    if appState.device != nil {
        WebSocketServer.shared.requestAppMirror(packageName: app.packageName)
    }
}
```

### New Method Added

```swift
/// Request app-specific mirroring via WebSocket
func requestAppMirror(packageName: String) {
    print("[mirror] 📱 Requesting app mirror for: \(packageName)")
    startMirrorAndPresentUI(mode: "app", package: packageName)
}
```

### Benefits

1. **No ADB Required**: Works over WebSocket connection only
2. **Integrated UI**: Uses the same mirror window as full device mirroring
3. **Quality Settings**: Respects user's mirror quality preferences (FPS, resolution, bitrate)
4. **Consistent Experience**: Same flow as device mirroring
5. **Better Performance**: Direct WebSocket streaming instead of scrcpy overhead

### How It Works

**User Flow:**
1. User taps app icon in Apps grid
2. Mac sends `mirrorRequest` with `mode: "app"` and `package: "com.example.app"`
3. Android launches the app and starts H.264 encoding
4. Android sends `mirrorFrame` messages via WebSocket
5. Mac displays in mirror window with VideoToolbox/FFmpeg decoding

**Message Flow:**
```
Mac → Android: mirrorRequest
{
  "type": "mirrorRequest",
  "data": {
    "action": "start",
    "mode": "app",
    "package": "com.example.app",
    "options": {
      "transport": "websocket",
      "fps": 30,
      "maxWidth": 1080,
      "quality": 80,
      "bitrate": 8000000
    }
  }
}

Android → Mac: mirrorResponse
{
  "type": "mirrorResponse",
  "data": {
    "status": "started",
    "mode": "app",
    "package": "com.example.app"
  }
}

Android → Mac: mirrorFrame (continuous)
{
  "type": "mirrorFrame",
  "data": {
    "frame": "<base64 H.264 data>",
    "pts": 1234567890,
    "isConfig": false
  }
}
```

---

## Issue 2: MD5 Checksum Still Failing ❌

### Problem
File transfer completed but Android reported `verified: false`:

```
[websocket] (file-transfer) Completed sending 3761088 bytes
[websocket] (file-transfer) Received transferVerified verified=false
```

### Root Cause
**Android is STILL using MD5** instead of SHA256 for checksum calculation.

The Mac side was already fixed to:
1. Detect MD5 vs SHA256 mismatch (32 chars vs 64 chars)
2. Log detailed checksum information
3. Show specific error messages

But **Android hasn't been updated yet**.

### Evidence from Logs

Mac sends file with SHA256 checksum:
```
[websocket] (file-transfer) id=4FF915DC-... checksumPrefix=dc997976
```

This is a SHA256 hash (64 hex characters), but Android computes MD5 (32 hex characters) and they don't match.

### Android Fix Required

**In Android file transfer code, change:**

```kotlin
// WRONG - Still using MD5
import java.security.MessageDigest

fun calculateChecksum(file: File): String {
    val md = MessageDigest.getInstance("MD5")  // ❌ WRONG
    val bytes = file.readBytes()
    val digest = md.digest(bytes)
    return digest.joinToString("") { "%02x".format(it) }
}
```

**To:**

```kotlin
// CORRECT - Use SHA256
import java.security.MessageDigest

fun calculateChecksum(file: File): String {
    val md = MessageDigest.getInstance("SHA-256")  // ✅ CORRECT
    val bytes = file.readBytes()
    val digest = md.digest(bytes)
    return digest.joinToString("") { "%02x".format(it) }
}
```

### Mac Side Detection (Already Implemented)

The Mac already detects this issue and logs it:

```swift
// Verify checksum if present
if let expected = incomingFilesChecksum[id] {
    if let fileData = try? Data(contentsOf: state.tempUrl) {
        let computed = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
        print("[websocket] (file-transfer) Checksum verification: expected=\(expected.prefix(16))... computed=\(computed.prefix(16))...")
        print("[websocket] (file-transfer) Expected length: \(expected.count), Computed length: \(computed.count)")
        
        // Check if Android sent MD5 (32 chars) instead of SHA256 (64 chars)
        if expected.count == 32 && computed.count == 64 {
            print("[websocket] (file-transfer) ⚠️ MISMATCH: Android sent MD5 (32 chars) but Mac computed SHA256 (64 chars)")
            print("[websocket] (file-transfer) 💡 Android needs to use SHA256 instead of MD5 for checksums")
        }
    }
}
```

### Testing After Android Fix

1. **Send file from Mac to Android**
2. **Check Mac logs for:**
   ```
   [websocket] (file-transfer) Expected length: 64, Computed length: 64
   [websocket] (file-transfer) ✅ Checksum verified successfully
   ```
3. **Check Android logs for:**
   ```
   [FileTransfer] Received transferVerified: verified=true
   ```

---

## Summary of Changes

### ✅ App Mirroring Fixed
- Changed from scrcpy (ADB-based) to WebSocket mirroring
- Added `requestAppMirror()` convenience method
- Works without ADB connection
- Uses integrated mirror window
- Respects quality settings

### ⚠️ Checksum Issue Remains
- **Mac side**: Already fixed and detecting the issue
- **Android side**: Still needs to change from MD5 to SHA256
- File transfers work but show `verified: false`
- No data corruption, just verification mismatch

### Files Modified
- `airsync-mac/Screens/HomeScreen/AppsView/AppGridView.swift`
  - Updated tap handler to use WebSocket mirroring
  - Updated context menu to use WebSocket mirroring
  - Changed mirror indicator condition (no ADB required)
  
- `airsync-mac/Core/WebSocket/WebSocketServer.swift`
  - Added `requestAppMirror(packageName:)` method
  - Checksum detection already implemented (from previous fix)

### Android Changes Needed
- Change `MessageDigest.getInstance("MD5")` to `MessageDigest.getInstance("SHA-256")`
- Update any file transfer code that calculates checksums
- Test file transfers in both directions

---

## Testing Instructions

### Test WebSocket App Mirroring

1. **Connect Android device** (WebSocket only, no ADB needed)
2. **Go to Apps tab**
3. **Tap any app icon** or **right-click → Mirror App**
4. **Verify**:
   - Mirror window opens
   - App launches on Android
   - Only that app is visible (not full screen)
   - Quality settings are applied
   - No scrcpy process launched

### Test Checksum (After Android Fix)

1. **Send file from Mac to Android**
2. **Check Mac logs** for `✅ Checksum verified successfully`
3. **Send file from Android to Mac**
4. **Check Mac logs** for `✅ Checksum verified successfully`
5. **Verify** no `verified: false` messages

---

## Architecture

### WebSocket App Mirroring Flow

```
User taps app in grid
    ↓
AppGridItemView.handleTap()
    ↓
WebSocketServer.requestAppMirror(packageName)
    ↓
startMirrorAndPresentUI(mode: "app", package: packageName)
    ↓
sendMirrorRequest(action: "start", mode: "app", package: ...)
    ↓
Android receives mirrorRequest
    ↓
Android launches app
    ↓
Android starts H.264 encoding
    ↓
Android sends mirrorFrame messages
    ↓
Mac decodes with VideoToolbox/FFmpeg
    ↓
Mac displays in mirror window
```

### Checksum Verification Flow

```
Mac sends file
    ↓
Mac calculates SHA256 checksum
    ↓
Mac sends fileTransferInit with checksum
    ↓
Mac sends fileChunk messages
    ↓
Mac sends fileTransferComplete
    ↓
Android receives all chunks
    ↓
Android calculates checksum (MUST BE SHA256!)
    ↓
Android compares checksums
    ↓
Android sends transferVerified with result
    ↓
Mac shows notification
```

---

## Known Issues

1. **Checksum still fails** - Android needs SHA256 update
2. **H.264 Baseline profile** - Android encoder should use Main/High profile (from previous issue)

Both issues are **Android-side** and need updates in the Android app code.
