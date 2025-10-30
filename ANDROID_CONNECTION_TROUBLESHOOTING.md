# Android Connection Troubleshooting Guide

## Common Connection Issues

### 1. Check WebSocket Connection
The Android app needs to connect to the Mac's WebSocket server. Check these:

**Mac Side:**
- Server should be running on port 6996 (default)
- Check logs for: `[websocket] WebSocket server started at ws://[IP]:[PORT]/socket`
- Verify firewall isn't blocking port 6996

**Android Side:**
- Must connect to: `ws://[Mac_IP]:6996/socket`
- Check if Android app is trying to connect to correct IP
- Verify Android has network permissions

### 2. Message Encryption
The connection uses symmetric key encryption. Check:

**Mac Side:**
```swift
// In WebSocketServer.swift, check if key is loaded:
print("[websocket] (auth) Loaded existing symmetric key")
```

**Android Side:**
- Must have the same symmetric key as Mac
- Key should be exchanged during pairing/QR code scan
- Messages must be encrypted before sending

### 3. First Message Must Be Device Info
Android must send device info as first message:

```json
{
    "type": "device",
    "data": {
        "name": "Device Name",
        "ipAddress": "192.168.1.x",
        "port": 8888,
        "version": "2.0.0",
        "wallpaper": "base64_encoded_image_optional"
    }
}
```

### 4. Message Format
All messages must follow this structure:

```json
{
    "type": "messageType",
    "data": {
        // message-specific data
    }
}
```

## Debugging Steps

### Step 1: Check Mac Server Status
Look for these log messages:
```
[websocket] WebSocket server started at ws://192.168.x.x:6996/socket
[websocket] Auto-selected network adapter: en0 -> 192.168.x.x
```

### Step 2: Check Android Connection Attempt
When Android tries to connect, Mac should log:
```
[websocket] Device connected
[websocket] Active sessions: 1
```

### Step 3: Check Message Reception
When Android sends device info, Mac should log:
```
[websocket] [raw] incoming text length=XXX
[websocket] [decrypt] used=true decryptedLen=XXX
[websocket] [received] {"type":"device","data":{...}}
```

### Step 4: Check Device Registration
After successful device message, Mac should log:
```
Device name: [Name]
IP: [IP]
Port: [Port]
Version: [Version]
```

## Common Problems & Solutions

### Problem 1: "Connection Refused" or "Cannot Connect"
**Symptoms:**
- Android can't connect to Mac
- No "Device connected" log on Mac

**Solutions:**
1. Verify both devices on same WiFi network
2. Check Mac firewall settings (System Settings > Network > Firewall)
3. Try disabling Mac firewall temporarily to test
4. Verify Mac IP address hasn't changed
5. Restart WebSocket server on Mac

### Problem 2: "Device Connected but No Data"
**Symptoms:**
- Mac logs "Device connected"
- But no device info appears in UI
- No further messages received

**Solutions:**
1. Check if Android is sending encrypted messages
2. Verify symmetric key matches on both sides
3. Check message format is correct JSON
4. Look for JSON decode errors in Mac logs

### Problem 3: "Messages Not Decrypting"
**Symptoms:**
- Mac receives messages but can't decrypt
- Logs show: `[websocket] [decrypt] used=true decryptedLen=0`

**Solutions:**
1. Verify symmetric key is identical on both sides
2. Check encryption algorithm matches (AES-GCM)
3. Ensure nonce/IV is included in encrypted message
4. Re-pair devices to generate new shared key

### Problem 4: "Mirror Not Starting"
**Symptoms:**
- Device connected successfully
- But mirror doesn't start or is black screen

**Solutions:**
1. Check Android has screen capture permissions
2. Verify H.264 encoder is working on Android
3. Check network bandwidth (try lower quality settings)
4. Look for Android encoder errors
5. Verify `mirrorStart` message is sent from Android

### Problem 5: "Input Events Not Working"
**Symptoms:**
- Mirror shows screen
- But clicks/taps don't work on Android

**Solutions:**
1. Check Android has Accessibility Service enabled
2. Verify `inputEvent` messages are being sent from Mac
3. Check Android is receiving and processing input events
4. Ensure coordinate mapping is correct (screen resolution)

## Testing Connection Step-by-Step

### Test 1: Basic WebSocket Connection
```kotlin
// Android side - test basic connection
val client = OkHttpClient()
val request = Request.Builder()
    .url("ws://[MAC_IP]:6996/socket")
    .build()
val listener = object : WebSocketListener() {
    override fun onOpen(webSocket: WebSocket, response: Response) {
        println("✅ Connected to Mac!")
    }
    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        println("❌ Connection failed: ${t.message}")
    }
}
client.newWebSocket(request, listener)
```

### Test 2: Send Device Info
```kotlin
// After connection opens
val deviceInfo = JSONObject().apply {
    put("type", "device")
    put("data", JSONObject().apply {
        put("name", "Test Device")
        put("ipAddress", "192.168.1.x")
        put("port", 8888)
        put("version", "2.0.0")
    })
}
val encrypted = encryptMessage(deviceInfo.toString(), symmetricKey)
webSocket.send(encrypted)
```

### Test 3: Verify Mac Receives
Check Mac logs for:
```
[websocket] [raw] incoming text length=XXX
[websocket] [decrypt] used=true decryptedLen=XXX
[websocket] [received] {"type":"device",...}
```

## Network Requirements

### Ports Used:
- **6996**: WebSocket server (Mac)
- **8888**: HTTP wake-up service (Android, optional)
- **8889**: UDP wake-up service (Android, optional)

### Firewall Rules Needed:
**Mac:**
- Allow incoming on port 6996 (TCP)

**Android:**
- Allow outgoing to port 6996 (TCP)
- Allow incoming on ports 8888, 8889 (optional, for quick connect)

## Encryption Details

### Symmetric Key Generation:
```swift
// Mac generates and stores key
let key = SymmetricKey(size: .bits256)
// Key is stored in Keychain
```

### Key Exchange:
1. Mac generates QR code containing:
   - Mac IP address
   - Port number
   - Base64-encoded symmetric key
2. Android scans QR code
3. Android extracts and stores symmetric key
4. Both sides use same key for encryption/decryption

### Message Encryption (AES-GCM):
```swift
// Mac side
func encryptMessage(_ message: String, using key: SymmetricKey) -> String? {
    guard let data = message.data(using: .utf8) else { return nil }
    let sealed = try? AES.GCM.seal(data, using: key)
    return sealed?.combined?.base64EncodedString()
}
```

## Getting More Debug Info

### Enable Verbose Logging on Mac:
Look for these log prefixes:
- `[websocket]` - WebSocket events
- `[mirror]` - Mirroring events
- `[quick-connect]` - Connection attempts
- `[state]` - App state changes

### Check Android Logs:
```bash
adb logcat | grep -i "airsync\|websocket\|mirror"
```

## Still Having Issues?

If connection still fails after trying above steps:

1. **Capture network traffic** using Wireshark to see if packets are reaching Mac
2. **Test with simple WebSocket client** (like Postman) to verify Mac server works
3. **Check Android app permissions** - Network, Accessibility, Screen Capture
4. **Verify Android app version** matches Mac app version requirements
5. **Try different WiFi network** to rule out network restrictions

## Quick Diagnostic Checklist

- [ ] Both devices on same WiFi network
- [ ] Mac WebSocket server running (check logs)
- [ ] Mac firewall allows port 6996
- [ ] Android has network permissions
- [ ] Symmetric key matches on both sides
- [ ] Android sends device info as first message
- [ ] Messages are properly encrypted
- [ ] JSON format is correct
- [ ] Android has Accessibility Service enabled (for input)
- [ ] Android has Screen Capture permission (for mirroring)
