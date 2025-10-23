# AirSync API and WebSocket Protocol Specification

## Overview

This document provides complete technical specifications for the AirSync protocol, enabling developers to build server implementations, client libraries, and command-line tools for any operating system. AirSync uses a WebSocket-based protocol for real-time bidirectional communication between Mac and Android devices.

**Protocol:** WebSocket (RFC 6455)
**Encryption:** AES-256-GCM
**Message Format:** JSON
**Default Port:** 5297
**Endpoint:** `/socket`

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Authentication and Connection Flow](#authentication-and-connection-flow)
3. [Encryption](#encryption)
4. [Message Protocol](#message-protocol)
5. [Message Types Reference](#message-types-reference)
6. [File Transfer Protocol](#file-transfer-protocol)
7. [Implementation Examples](#implementation-examples)
8. [Implementation Guide](#implementation-guide)
9. [Quick Reference](#quick-reference)

---

## Quick Start

### Connection Sequence

1. Connect WebSocket client to `ws://<mac_ip>:5297/socket`
2. Send `device` message with device information
3. Receive `macInfo` response from server
4. Connection ready for bidirectional communication

### First Message (Device)

```json
{
  "type": "device",
  "data": {
    "name": "My Device",
    "ipAddress": "192.168.1.100",
    "port": 8090,
    "version": "2.0.0"
  }
}
```

### Common Commands

Control media playback:

```json
{"type": "mediaControl", "data": {"action": "play"}}
{"type": "mediaControl", "data": {"action": "next"}}
```

Adjust volume:

```json
{"type": "volumeControl", "data": {"action": "volumeUp"}}
{"type": "volumeControl", "data": {"action": "setVolume", "volume": 50}}
```

---

## Authentication and Connection Flow

### Device Discovery

An Android client discovers the Mac server through one of three methods:

- Bonjour (mDNS) service discovery on the local network
- Manual IP and port entry provided by the user
- Quick Connect using previous connection history stored locally

### WebSocket Connection Establishment

The client initiates a WebSocket connection:

```
ws://<mac_ip>:<port>/socket
```

The connection follows this sequence:

1. Client sends WebSocket HTTP upgrade request
2. Server accepts and assigns a WebSocketSession
3. Server loads/generates symmetric encryption key (if encryption enabled)
4. Client sends initial `device` message with device information
5. Server responds with `macInfo` message containing Mac details
6. Connection established and ready for bidirectional communication

### License Verification

License status is tracked internally by the Mac server through the device's pairing history and subscription status. On initial connection, the `hasPairedDeviceOnce` flag is set. Plus features are verified through `AppState.shared.isPlus`.

---

## Encryption

AirSync implements optional end-to-end encryption using AES-256-GCM, a NIST-approved authenticated encryption algorithm.

### Key Management

On first startup, the server generates a 256-bit symmetric key that is:

- Persisted in UserDefaults under the key "encryptionKey" in Base64 format
- Reloaded on subsequent server startups
- Can be reset programmatically via `resetSymmetricKey()`

### Encryption and Decryption Process

All messages are encrypted using the same symmetric key. The encryption process generates a unique 96-bit nonce for each message:

**Encryption flow:**

```
plaintext → UTF-8 encode → AES-256-GCM seal (generates nonce)
→ combined (nonce + ciphertext + authentication tag) → Base64 encode → send
```

**Decryption flow:**

```
received → Base64 decode → AES-256-GCM unseal → UTF-8 decode → plaintext
```

### Retrieving the Encryption Key

```swift
func getSymmetricKeyBase64() -> String?
```

### Python Encryption Implementation

```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os
import base64

def encrypt_message(message: str, key_base64: str) -> str:
    key = base64.b64decode(key_base64)
    nonce = os.urandom(12)  # 96-bit nonce
    cipher = AESGCM(key)
    ciphertext = cipher.encrypt(nonce, message.encode(), None)
    combined = nonce + ciphertext  # includes tag
    return base64.b64encode(combined).decode()

def decrypt_message(encrypted_base64: str, key_base64: str) -> str:
    key = base64.b64decode(key_base64)
    combined = base64.b64decode(encrypted_base64)
    nonce = combined[:12]
    ciphertext = combined[12:]
    cipher = AESGCM(key)
    plaintext = cipher.decrypt(nonce, ciphertext, None)
    return plaintext.decode()
```

### JavaScript/Node.js Encryption Implementation

```javascript
const crypto = require("crypto");

function encryptMessage(message, keyBase64) {
  const key = Buffer.from(keyBase64, "base64");
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);

  let encrypted = cipher.update(message, "utf8", "binary");
  encrypted += cipher.final("binary");

  const tag = cipher.getAuthTag();
  const combined = Buffer.concat([
    nonce,
    Buffer.from(encrypted, "binary"),
    tag,
  ]);
  return combined.toString("base64");
}

function decryptMessage(encryptedBase64, keyBase64) {
  const key = Buffer.from(keyBase64, "base64");
  const combined = Buffer.from(encryptedBase64, "base64");

  const nonce = combined.slice(0, 12);
  const ciphertext = combined.slice(12, -16);
  const tag = combined.slice(-16);

  const decipher = crypto.createDecipheriv("aes-256-gcm", key, nonce);
  decipher.setAuthTag(tag);

  let decrypted = decipher.update(ciphertext, "binary", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}
```

---

## Message Protocol

### General Message Structure

All messages follow a consistent JSON structure:

```json
{
  "type": "<MessageType>",
  "data": {}
}
```

The `type` field specifies the message category, and the `data` object contains type-specific fields.

### Message Transmission

When encryption is enabled:

```
JSON string → UTF-8 encode → AES-256-GCM encrypt → Base64 encode → WebSocket text frame
```

When encryption is disabled:

```
JSON string → WebSocket text frame
```

### Message Types Summary

| Type                         | Direction     | Purpose                                 |
| ---------------------------- | ------------- | --------------------------------------- |
| `device`                     | Android → Mac | Device identification and handshake     |
| `macInfo`                    | Mac → Android | Mac device information and capabilities |
| `notification`               | Android → Mac | Push notification event                 |
| `notificationAction`         | Mac → Android | User interaction with notification      |
| `notificationActionResponse` | Android → Mac | Result of notification action           |
| `notificationUpdate`         | Android → Mac | Notification state change               |
| `status`                     | Android → Mac | Device status: battery, music, pairing  |
| `dismissalResponse`          | Android → Mac | Notification dismissal confirmation     |
| `mediaControl`               | Mac → Android | Android media playback control          |
| `mediaControlResponse`       | Android → Mac | Media control execution result          |
| `macMediaControl`            | Android → Mac | Mac media playback control              |
| `macMediaControlResponse`    | Mac → Android | Mac media control result                |
| `volumeControl`              | Mac → Android | Device volume adjustment                |
| `appIcons`                   | Android → Mac | Application list with icons             |
| `clipboardUpdate`            | Android → Mac | Clipboard content synchronization       |
| `fileTransferInit`           | Either        | Initiate file transfer session          |
| `fileChunk`                  | Either        | File data chunk in Base64               |
| `fileChunkAck`               | Either        | Acknowledge received chunk              |
| `fileTransferComplete`       | Either        | File transfer completion signal         |
| `transferVerified`           | Either        | Checksum verification result            |
| `wakeUpRequest`              | Mac → Android | Wake device from sleep                  |
| `toggleAppNotif`             | Mac → Android | Enable/disable app notifications        |
| `disconnectRequest`          | Mac → Android | Request graceful disconnection          |

---

## Message Types Reference

### 1. Device Message

**Direction:** Android → Mac (Required first message)

**Purpose:** Device identification and connection handshake

```json
{
  "type": "device",
  "data": {
    "name": "Pixel 6 Pro",
    "ipAddress": "192.168.1.100",
    "port": 8090,
    "version": "2.0.0",
    "wallpaper": "[optional base64 image data]"
  }
}
```

This message must be sent immediately after connection establishment. The server automatically responds with a `macInfo` message.

---

### 2. MacInfo Message

**Direction:** Mac → Android

**Purpose:** Provide Mac device information and capabilities

```json
{
  "type": "macInfo",
  "data": {
    "name": "Sameera's MacBook Pro",
    "categoryType": "MacBook Pro",
    "exactDeviceName": "MacBook Pro (14-inch, 2023)",
    "model": "MacBook Pro (14-inch, 2023)",
    "type": "MacBook Pro",
    "isPlus": true,
    "isPlusSubscription": true,
    "savedAppPackages": ["com.spotify", "com.apple.music"]
  }
}
```

---

### 3. Notification Message

**Direction:** Android → Mac

**Purpose:** Deliver push notification from Android device

```json
{
  "type": "notification",
  "data": {
    "id": "n_12345",
    "title": "Message from John",
    "body": "Hey, how are you?",
    "app": "WhatsApp",
    "package": "com.whatsapp",
    "nid": "notif_uuid_string",
    "actions": [
      {
        "name": "reply",
        "type": "reply"
      },
      {
        "name": "dismiss",
        "type": "button"
      }
    ]
  }
}
```

---

### 4. Notification Action

**Direction:** Mac → Android

**Purpose:** User interacts with notification through Mac UI

```json
{
  "type": "notificationAction",
  "data": {
    "id": "n_12345",
    "name": "reply",
    "text": "Thanks, I'm doing great!"
  }
}
```

For button-only actions without reply text:

```json
{
  "type": "notificationAction",
  "data": {
    "id": "n_12345",
    "name": "dismiss"
  }
}
```

---

### 5. Notification Action Response

**Direction:** Android → Mac

**Purpose:** Confirm that notification action was processed successfully

```json
{
  "type": "notificationActionResponse",
  "data": {
    "id": "n_12345",
    "action": "reply",
    "success": true,
    "message": "Reply sent successfully"
  }
}
```

---

### 6. Notification Update

**Direction:** Android → Mac

**Purpose:** Signal notification state change such as dismissal on Android

```json
{
  "type": "notificationUpdate",
  "data": {
    "id": "n_12345",
    "action": "dismiss",
    "dismissed": true
  }
}
```

---

### 7. Status Message

**Direction:** Android → Mac

**Purpose:** Report device state: battery level, music playback status, and pairing information

```json
{
  "type": "status",
  "data": {
    "isPaired": true,
    "battery": {
      "level": 85,
      "isCharging": true
    },
    "music": {
      "isPlaying": true,
      "title": "Bohemian Rhapsody",
      "artist": "Queen",
      "volume": 75,
      "isMuted": false,
      "albumArt": "data:image/png;base64,iVBORw0KG...",
      "likeStatus": "liked"
    }
  }
}
```

---

### 8. Media Control

**Direction:** Mac → Android

**Purpose:** Control playback on Android device

```json
{
  "type": "mediaControl",
  "data": {
    "action": "play"
  }
}
```

Supported actions:

- `play` - Start playback
- `pause` - Pause playback
- `playPause` - Toggle play/pause
- `next` - Skip to next track
- `previous` - Go to previous track
- `stop` - Stop playback
- `like` - Mark current track as liked
- `unlike` - Remove like from current track
- `toggleLike` - Toggle like status

---

### 9. Media Control Response

**Direction:** Android → Mac

**Purpose:** Confirm execution of media control command

```json
{
  "type": "mediaControlResponse",
  "data": {
    "action": "play",
    "success": true
  }
}
```

---

### 10. Mac Media Control

**Direction:** Android → Mac

**Purpose:** Control Mac media playback

```json
{
  "type": "macMediaControl",
  "data": {
    "action": "play"
  }
}
```

Supported actions: `play`, `pause`, `previous`, `next`, `stop`

---

### 11. Mac Media Control Response

**Direction:** Mac → Android

**Purpose:** Confirm execution of Mac media control command

```json
{
  "type": "macMediaControlResponse",
  "data": {
    "action": "play",
    "success": true
  }
}
```

---

### 12. Volume Control

**Direction:** Mac → Android

**Purpose:** Adjust device volume or mute status

```json
{
  "type": "volumeControl",
  "data": {
    "action": "volumeUp"
  }
}
```

Supported actions:

- `volumeUp` - Increase volume
- `volumeDown` - Decrease volume
- `mute` - Mute device
- `setVolume` - Set specific volume level (requires `volume` field 0-100)

Example with specific volume level:

```json
{
  "type": "volumeControl",
  "data": {
    "action": "setVolume",
    "volume": 50
  }
}
```

---

### 13. App Icons

**Direction:** Android → Mac

**Purpose:** Deliver app list with metadata and icons

```json
{
  "type": "appIcons",
  "data": {
    "com.spotify": {
      "name": "Spotify",
      "icon": "iVBORw0KGgoAAAANSUhEUgAA...",
      "systemApp": false,
      "listening": true
    },
    "com.whatsapp": {
      "name": "WhatsApp",
      "icon": "iVBORw0KGgoAAAANSUhEUgAA...",
      "systemApp": false,
      "listening": true
    }
  }
}
```

Fields:

- `icon` - Base64-encoded PNG image
- `systemApp` - Boolean indicating if this is a system application
- `listening` - Boolean indicating if notifications are enabled for this app

---

### 14. Clipboard Update

**Direction:** Android → Mac

**Purpose:** Synchronize clipboard content

```json
{
  "type": "clipboardUpdate",
  "data": {
    "text": "Clipboard content here"
  }
}
```

---

### 15. Toggle App Notifications

**Direction:** Mac → Android

**Purpose:** Enable or disable notifications for a specific application

```json
{
  "type": "toggleAppNotif",
  "data": {
    "package": "com.spotify",
    "state": true
  }
}
```

---

### 16. Dismiss Notification

**Direction:** Mac → Android

**Purpose:** Dismiss a notification on the Android device

```json
{
  "type": "dismissNotification",
  "data": {
    "id": "n_12345"
  }
}
```

---

### 17. Dismissal Response

**Direction:** Android → Mac

**Purpose:** Confirm dismissal of notification

```json
{
  "type": "dismissalResponse",
  "data": {
    "id": "n_12345",
    "success": true
  }
}
```

---

### 18. Disconnect Request

**Direction:** Mac → Android

**Purpose:** Request graceful disconnection from the server

```json
{
  "type": "disconnectRequest",
  "data": {}
}
```

---

## File Transfer Protocol

File transfers in AirSync are implemented with reliability mechanisms including chunked transmission, checksums, and sliding window acknowledgments.

### Features

- Bidirectional transfer (Mac to Android and Android to Mac)
- Chunked transmission (64 KB chunks)
- SHA256 checksum verification
- Sliding window acknowledgment (8 chunks maximum in-flight)
- Automatic retry (3 attempts per chunk)
- Base64 encoding for JSON transport

### File Transfer Init

Initiates a file transfer session with file metadata and checksum.

```json
{
  "type": "fileTransferInit",
  "data": {
    "id": "transfer_uuid_abc123",
    "name": "document.pdf",
    "size": 2097152,
    "mime": "application/pdf",
    "checksum": "a1b2c3d4e5f6..."
  }
}
```

Fields:

- `id` - Unique transfer identifier (UUID)
- `name` - Original filename
- `size` - Total file size in bytes
- `mime` - MIME type (optional)
- `checksum` - SHA256 hexadecimal hash (optional but recommended)

### File Chunk

Sends a chunk of file data during transfer.

```json
{
  "type": "fileChunk",
  "data": {
    "id": "transfer_uuid_abc123",
    "index": 0,
    "chunk": "SGVsbG8gV29ybGQhIFRoaXMgaXMgYSB0ZXN0IGZpbGUgY29udGVudC4="
  }
}
```

Fields:

- `id` - Matches the fileTransferInit `id`
- `index` - Chunk sequence number (0-based)
- `chunk` - Base64-encoded file data

Default chunk size is 64 KB. The sender maintains a sliding window allowing up to 8 chunks to be in-flight before waiting for acknowledgments.

### File Chunk Acknowledgment

Receiver acknowledges successful receipt and processing of a chunk.

```json
{
  "type": "fileChunkAck",
  "data": {
    "id": "transfer_uuid_abc123",
    "index": 0
  }
}
```

The sender processes acknowledgments to implement sliding window flow control:

1. Sender transmits chunks 0-7 (window size = 8)
2. Receiver processes and acknowledges chunk 0
3. Sender immediately transmits chunk 8
4. Receiver continues processing and acknowledging chunks
5. Sender maintains the sliding window throughout transfer

### File Transfer Complete

Signals completion of file transmission.

```json
{
  "type": "fileTransferComplete",
  "data": {
    "id": "transfer_uuid_abc123",
    "name": "document.pdf",
    "size": 2097152,
    "checksum": "a1b2c3d4e5f6..."
  }
}
```

### Transfer Verified

Receiver confirms file integrity by verifying checksum match.

```json
{
  "type": "transferVerified",
  "data": {
    "id": "transfer_uuid_abc123",
    "verified": true
  }
}
```

If checksum verification fails:

```json
{
  "type": "transferVerified",
  "data": {
    "id": "transfer_uuid_abc123",
    "verified": false
  }
}
```

### Complete Transfer Sequence

```
1. Sender → Receiver: fileTransferInit
   id: abc123, name: photo.jpg, size: 1048576, checksum: 5f83...

2. Sender → Receiver: fileChunk (index 0-7)
3. Receiver → Sender: fileChunkAck (index 0)
4. Sender → Receiver: fileChunk (index 8)
   ... continue with sliding window ...

N. Sender → Receiver: fileTransferComplete
   checksum: 5f83...

N+1. Receiver → Sender: transferVerified (verified: true)
```

### Checksum Calculation

```python
import hashlib

def calculate_checksum(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()
```

---

## Implementation Examples

### Python Client

```python
import json
import websocket
import threading
import base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

class AirSyncClient:
    def __init__(self, host, port, encryption_key=None):
        self.host = host
        self.port = port
        self.key = base64.b64decode(encryption_key) if encryption_key else None
        self.ws = None
        self.connected = False

    def connect(self):
        url = f"ws://{self.host}:{self.port}/socket"
        self.ws = websocket.WebSocketApp(
            url,
            on_message=self.on_message,
            on_error=self.on_error,
            on_close=self.on_close,
            on_open=self.on_open
        )
        self.wst = threading.Thread(target=self.ws.run_forever)
        self.wst.daemon = True
        self.wst.start()

    def on_open(self, ws):
        self.connected = True
        print("Connected to AirSync server")
        self.send_device_message()

    def on_message(self, ws, message):
        msg_dict = self.decrypt_and_decode(message)
        if msg_dict['type'] == 'macInfo':
            print(f"Connected to {msg_dict['data']['name']}")

    def on_error(self, ws, error):
        print(f"Error: {error}")

    def on_close(self, ws, close_status_code, close_msg):
        self.connected = False
        print("Disconnected from AirSync server")

    def send_device_message(self):
        device_msg = {
            "type": "device",
            "data": {
                "name": "My Android Device",
                "ipAddress": "192.168.1.100",
                "port": 8090,
                "version": "2.0.0"
            }
        }
        self.send_message(device_msg)

    def send_message(self, msg_dict):
        json_str = json.dumps(msg_dict)
        if self.key:
            encrypted = self.encrypt_message(json_str)
        else:
            encrypted = json_str
        self.ws.send(encrypted)

    def encrypt_message(self, message):
        nonce = os.urandom(12)
        cipher = AESGCM(self.key)
        ciphertext = cipher.encrypt(nonce, message.encode(), None)
        combined = nonce + ciphertext
        return base64.b64encode(combined).decode()

    def decrypt_and_decode(self, message):
        if self.key:
            try:
                combined = base64.b64decode(message)
                nonce = combined[:12]
                ciphertext = combined[12:]
                cipher = AESGCM(self.key)
                plaintext = cipher.decrypt(nonce, ciphertext, None)
                return json.loads(plaintext.decode())
            except:
                return json.loads(message)
        else:
            return json.loads(message)

    def send_media_control(self, action):
        msg = {
            "type": "mediaControl",
            "data": {"action": action}
        }
        self.send_message(msg)

# Usage
client = AirSyncClient("192.168.1.50", 5297)
client.connect()
client.send_media_control("play")
```

### JavaScript/Node.js Client

```javascript
const WebSocket = require("ws");
const crypto = require("crypto");

class AirSyncClient {
  constructor(host, port, encryptionKey = null) {
    this.host = host;
    this.port = port;
    this.key = encryptionKey ? Buffer.from(encryptionKey, "base64") : null;
    this.ws = null;
    this.connected = false;
  }

  connect() {
    const url = `ws://${this.host}:${this.port}/socket`;
    this.ws = new WebSocket(url);

    this.ws.on("open", () => this.onOpen());
    this.ws.on("message", (msg) => this.onMessage(msg));
    this.ws.on("error", (error) => this.onError(error));
    this.ws.on("close", () => this.onClose());
  }

  onOpen() {
    this.connected = true;
    console.log("Connected to AirSync server");
    this.sendDeviceMessage();
  }

  onMessage(rawMessage) {
    const msgDict = this.decryptAndDecode(rawMessage);
    if (msgDict.type === "macInfo") {
      console.log(`Connected to ${msgDict.data.name}`);
    }
  }

  onError(error) {
    console.error("Error:", error);
  }

  onClose() {
    this.connected = false;
    console.log("Disconnected from AirSync server");
  }

  sendDeviceMessage() {
    const deviceMsg = {
      type: "device",
      data: {
        name: "My Android Device",
        ipAddress: "192.168.1.100",
        port: 8090,
        version: "2.0.0",
      },
    };
    this.sendMessage(deviceMsg);
  }

  sendMessage(msgDict) {
    const jsonStr = JSON.stringify(msgDict);
    const toSend = this.key ? this.encryptMessage(jsonStr) : jsonStr;
    this.ws.send(toSend);
  }

  encryptMessage(message) {
    const nonce = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", this.key, nonce);

    let encrypted = cipher.update(message, "utf8", "binary");
    encrypted += cipher.final("binary");

    const tag = cipher.getAuthTag();
    const combined = Buffer.concat([
      nonce,
      Buffer.from(encrypted, "binary"),
      tag,
    ]);

    return combined.toString("base64");
  }

  decryptAndDecode(rawMessage) {
    if (this.key) {
      try {
        const combined = Buffer.from(rawMessage, "base64");
        const nonce = combined.slice(0, 12);
        const ciphertext = combined.slice(12, -16);
        const tag = combined.slice(-16);

        const decipher = crypto.createDecipheriv(
          "aes-256-gcm",
          this.key,
          nonce
        );
        decipher.setAuthTag(tag);

        let decrypted = decipher.update(ciphertext, "binary", "utf8");
        decrypted += decipher.final("utf8");

        return JSON.parse(decrypted);
      } catch (e) {
        return JSON.parse(rawMessage);
      }
    } else {
      return JSON.parse(rawMessage);
    }
  }

  sendMediaControl(action) {
    const msg = {
      type: "mediaControl",
      data: { action },
    };
    this.sendMessage(msg);
  }
}

// Usage
const client = new AirSyncClient("192.168.1.50", 5297);
client.connect();
client.sendMediaControl("play");
```

---

## Implementation Guide

### Requirements Checklist

- [ ] WebSocket server listening on port 5297 (configurable)
- [ ] Message encryption using AES-256-GCM
- [ ] JSON message parsing and validation
- [ ] Session management (multiple concurrent clients)
- [ ] Message routing to active sessions
- [ ] File transfer with chunk acknowledgment
- [ ] Checksum verification (SHA256)
- [ ] Graceful connection handling

### Recommended Libraries

**Python:**

```bash
pip install websocket-server cryptography
```

**Node.js:**

```bash
npm install ws crypto
```

**Go:**

```bash
go get github.com/gorilla/websocket
go get github.com/awnumar/memguard
```

**Rust:**

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.20"
aes-gcm = "0.10"
```

### Connection Lifecycle

```
1. Start WebSocket server on Mac and generate QR code for pairing
2. Android device scans QR code and initiates connection with device info message
3. Mac receives device message and sends back macInfo message
4. Android compares app list from macInfo response and sends appIcons message if there are mismatches
5. Start regular listeners and polling for:
   - Notifications from Android
   - Media info updates from Android
   - Device status (battery, music, etc.) from Android
   - Device info updates from Android
   - Bidirectional clipboard and other service messages
6. Handle on-demand messages for features such as:
   - Clipboard synchronization
   - File transfer
   - Media control
   - Volume control
   - And other feature-specific commands
7. Disconnect request can be made from Mac to Android
8. Optional: Use reconnect feature to send reconnection message to Android if it can receive it,
   initiate device info message remotely, and repeat the flow from step 3
9. Connection closed (explicit or network error)
10. Cleanup: remove session, free resources
```

### Error Handling

Connection Errors:

- Invalid host/port: Connection refused
- Network unreachable: Socket error
- Timeout: Close after 30 seconds inactivity

Message Errors:

- Invalid JSON: Log and ignore (don't disconnect)
- Unknown message type: Log warning
- Decryption failure: Log error and close connection
- Missing required fields: Validate and reject

File Transfer Errors:

- Checksum mismatch: Notify user and request retry
- Chunk timeout: Retry up to 3 times
- Transfer size exceeded: Reject and close

### Testing Implementation

Manual WebSocket Test:

```bash
npm install -g wscat
wscat -c ws://192.168.1.50:5297/socket

# Send device message
{
  "type": "device",
  "data": {
    "name": "Test Device",
    "ipAddress": "192.168.1.100",
    "port": 8090,
    "version": "2.0.0"
  }
}
```

Automated Test Suite:

- Test each message type
- Test encryption/decryption roundtrip
- Test file transfer with various sizes
- Test concurrent connections
- Test error conditions

Integration Testing:

- Connect real Android device
- Verify all message types received correctly
- Verify all commands executed on Android
- Test with network interruptions
- Monitor for memory leaks in long-running tests

---

## Quick Reference

### Default Configuration

```
Port:           5297
Encryption:     AES-256-GCM
Message Format: JSON
Endpoint:       /socket
Chunk Size:     64 KB
Window Size:    8 chunks
Max Retries:    3
Timeout:        30 seconds
```

### Common Workflows

**Control Music Playback:**

```json
{"type": "mediaControl", "data": {"action": "play"}}
{"type": "mediaControl", "data": {"action": "next"}}
{"type": "mediaControl", "data": {"action": "volumeUp"}}
```

**Send File Transfer:**

```json
{"type": "fileTransferInit", "data": {"id": "uuid", "name": "file.pdf", "size": 1024000, "checksum": "sha256hex"}}
{"type": "fileChunk", "data": {"id": "uuid", "index": 0, "chunk": "base64data"}}
{"type": "fileChunkAck", "data": {"id": "uuid", "index": 0}}
{"type": "fileTransferComplete", "data": {"id": "uuid", "name": "file.pdf", "size": 1024000, "checksum": "sha256hex"}}
{"type": "transferVerified", "data": {"id": "uuid", "verified": true}}
```

**Sync Notifications:**

```json
{"type": "notification", "data": {"id": "n_123", "title": "Message", "body": "Content", "app": "WhatsApp"}}
{"type": "notificationAction", "data": {"id": "n_123", "name": "reply", "text": "Reply text"}}
{"type": "notificationActionResponse", "data": {"id": "n_123", "action": "reply", "success": true}}
```

---

**Document Version:** 2.1.3
**Last Updated:** October 23, 2025
**Protocol Status:** Stable
