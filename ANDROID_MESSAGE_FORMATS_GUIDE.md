# Android Message Formats - Complete Guide

## Overview

This guide shows the exact JSON format that Android should send to Mac for all features. Each section includes:
- Message structure
- Example with real data
- Field descriptions
- Common pitfalls

---

## 1. Health Data

### Request from Mac
```json
{
  "type": "requestHealthSummary",
  "data": {
    "date": 1735689600000
  }
}
```

**Fields:**
- `date`: Timestamp in milliseconds for the requested date

### Response from Android

```json
{
  "type": "healthSummary",
  "data": {
    "date": 1735689600000,
    "steps": 8542,
    "distance": 6.2,
    "calories": 2150,
    "activeMinutes": 45,
    "heartRateAvg": 72,
    "heartRateMin": 58,
    "heartRateMax": 145,
    "sleepDuration": 420
  }
}
```

**Field Descriptions:**
- `date` (required): Timestamp in milliseconds - **MUST match the requested date**
- `steps` (optional): Total steps for the day (integer)
- `distance` (optional): Distance in kilometers (double)
- `calories` (optional): Total calories burned (integer)
- `activeMinutes` (optional): Active minutes (integer)
- `heartRateAvg` (optional): Average heart rate in bpm (integer, use `null` or omit if no data)
- `heartRateMin` (optional): Minimum heart rate in bpm (integer, use `null` or omit if no data)
- `heartRateMax` (optional): Maximum heart rate in bpm (integer, use `null` or omit if no data)
- `sleepDuration` (optional): Sleep duration in minutes (integer)

**Important Notes:**
- ⚠️ **DO NOT send 0 for heart rate if no data** - use `null` or omit the field
- ⚠️ **Date MUST match the requested date**, not today's date
- All numeric fields can be `null` if no data available

### Example: No Data Available
```json
{
  "type": "healthSummary",
  "data": {
    "date": 1735689600000,
    "steps": null,
    "distance": null,
    "calories": null,
    "activeMinutes": null,
    "heartRateAvg": null,
    "heartRateMin": null,
    "heartRateMax": null,
    "sleepDuration": null
  }
}
```

### Example: Partial Data
```json
{
  "type": "healthSummary",
  "data": {
    "date": 1735689600000,
    "steps": 5420,
    "distance": 3.8,
    "calories": 890,
    "activeMinutes": 0,
    "heartRateAvg": null,
    "heartRateMin": null,
    "heartRateMax": null,
    "sleepDuration": 450
  }
}
```

---

## 2. SMS Threads

### Request from Mac
```json
{
  "type": "requestSmsThreads",
  "data": {
    "limit": 50
  }
}
```

### Response from Android

```json
{
  "type": "smsThreads",
  "data": {
    "threads": [
      {
        "threadId": "358",
        "address": "+919876543210",
        "contactName": "John Doe",
        "messageCount": 42,
        "snippet": "Hey, are you free tomorrow?",
        "date": 1735689600000,
        "unreadCount": 3
      },
      {
        "threadId": "357",
        "address": "VD-HDFCBK",
        "contactName": null,
        "messageCount": 15,
        "snippet": "Your account balance is Rs 5000.00",
        "date": 1735603200000,
        "unreadCount": 0
      },
      {
        "threadId": "356",
        "address": "+919123456789",
        "contactName": "Jane Smith",
        "messageCount": 128,
        "snippet": "Thanks for the help!",
        "date": 1735516800000,
        "unreadCount": 1
      }
    ]
  }
}
```

**Field Descriptions:**
- `threadId` (required): Unique thread identifier (string)
- `address` (required): Phone number or sender ID (string)
- `contactName` (optional): Contact name from address book (string or `null`)
- `messageCount` (required): Total messages in thread (integer)
- `snippet` (required): Preview of last message (string)
- `date` (required): Timestamp of last message in milliseconds (integer)
- `unreadCount` (required): Number of unread messages (integer, 0 if all read)

**Important Notes:**
- Use `null` for `contactName` if contact not found
- `snippet` should be truncated to ~100 characters
- `date` is the timestamp of the most recent message
- Sort threads by date (newest first)

---

## 3. Call Logs

### Request from Mac
```json
{
  "type": "requestCallLogs",
  "data": {
    "limit": 100,
    "since": 1735603200000
  }
}
```

**Fields:**
- `limit`: Maximum number of logs to return
- `since` (optional): Only return calls after this timestamp

### Response from Android

```json
{
  "type": "callLogs",
  "data": {
    "logs": [
      {
        "id": "1577",
        "number": "+911206647000",
        "contactName": null,
        "type": "missed",
        "date": 1735689600000,
        "duration": 0,
        "isRead": true
      },
      {
        "id": "1576",
        "number": "+919971319064",
        "contactName": "Satyam Webkul",
        "type": "outgoing",
        "date": 1735686400000,
        "duration": 125,
        "isRead": false
      },
      {
        "id": "1575",
        "number": "+919876543210",
        "contactName": "John Doe",
        "type": "incoming",
        "date": 1735683000000,
        "duration": 342,
        "isRead": true
      },
      {
        "id": "1574",
        "number": "+919123456789",
        "contactName": "Jane Smith",
        "type": "outgoing",
        "date": 1735679400000,
        "duration": 58,
        "isRead": true
      }
    ]
  }
}
```

**Field Descriptions:**
- `id` (required): Unique call log identifier (string)
- `number` (required): Phone number (string)
- `contactName` (optional): Contact name from address book (string or `null`)
- `type` (required): Call type - one of:
  - `"incoming"` - Received call
  - `"outgoing"` - Made call
  - `"missed"` - Missed call
  - `"voicemail"` - Voicemail
  - `"rejected"` - Rejected call
  - `"blocked"` - Blocked call
- `date` (required): Timestamp in milliseconds (integer)
- `duration` (required): Call duration in seconds (integer, 0 for missed/rejected)
- `isRead` (required): Whether call log has been viewed (boolean)

**Important Notes:**
- Use `null` for `contactName` if contact not found
- `duration` is 0 for missed, rejected, or blocked calls
- Sort logs by date (newest first)

---

## 4. Live Call Notifications

### Incoming Call
```json
{
  "type": "callNotification",
  "data": {
    "id": "call_12345",
    "number": "+919876543210",
    "contactName": "John Doe",
    "state": "ringing",
    "startTime": 1735689600000,
    "isIncoming": true
  }
}
```

### Active Call
```json
{
  "type": "callNotification",
  "data": {
    "id": "call_12345",
    "number": "+919876543210",
    "contactName": "John Doe",
    "state": "active",
    "startTime": 1735689600000,
    "isIncoming": true
  }
}
```

### Call Ended
```json
{
  "type": "callNotification",
  "data": {
    "id": "call_12345",
    "number": "+919876543210",
    "contactName": "John Doe",
    "state": "disconnected",
    "startTime": 1735689600000,
    "isIncoming": true
  }
}
```

**Field Descriptions:**
- `id` (required): Unique call identifier (string)
- `number` (required): Phone number (string)
- `contactName` (optional): Contact name (string or `null`)
- `state` (required): Call state - one of:
  - `"ringing"` - Incoming/outgoing call ringing
  - `"active"` - Call in progress
  - `"held"` - Call on hold
  - `"disconnected"` - Call ended
- `startTime` (required): When call started (timestamp in milliseconds)
- `isIncoming` (required): True for incoming, false for outgoing (boolean)

---

## 5. SMS Received (Live)

```json
{
  "type": "smsReceived",
  "data": {
    "id": "sms_67890",
    "threadId": "358",
    "address": "+919876543210",
    "contactName": "John Doe",
    "body": "Hey, are you free tomorrow?",
    "date": 1735689600000,
    "type": 1,
    "read": false
  }
}
```

**Field Descriptions:**
- `id` (required): Unique message identifier (string)
- `threadId` (required): Thread this message belongs to (string)
- `address` (required): Sender phone number (string)
- `contactName` (optional): Contact name (string or `null`)
- `body` (required): Message text (string)
- `date` (required): Timestamp in milliseconds (integer)
- `type` (required): Message type (integer)
  - `1` = Received
  - `2` = Sent
- `read` (required): Whether message has been read (boolean)

---

## 6. Device Status

### From Android to Mac
```json
{
  "type": "status",
  "data": {
    "battery": {
      "level": 75,
      "isCharging": false
    },
    "isPaired": true,
    "music": {
      "isPlaying": true,
      "title": "Bohemian Rhapsody",
      "artist": "Queen",
      "volume": 80,
      "isMuted": false,
      "albumArt": "base64_encoded_image_data_here",
      "likeStatus": "liked"
    }
  }
}
```

**Field Descriptions:**
- `battery.level` (required): Battery percentage 0-100 (integer)
- `battery.isCharging` (required): Charging status (boolean)
- `isPaired` (required): Connection status (boolean)
- `music.isPlaying` (required): Playback status (boolean)
- `music.title` (required): Song title (string, empty if not playing)
- `music.artist` (required): Artist name (string, empty if not playing)
- `music.volume` (required): Volume 0-100 (integer)
- `music.isMuted` (required): Mute status (boolean)
- `music.albumArt` (optional): Base64 encoded album art (string)
- `music.likeStatus` (optional): "liked", "disliked", or "none" (string)

---

## 7. Notifications

```json
{
  "type": "notification",
  "data": {
    "id": "notif_12345",
    "title": "New Message",
    "body": "Hey, how are you?",
    "app": "WhatsApp",
    "package": "com.whatsapp",
    "actions": [
      {
        "name": "Reply",
        "type": "reply"
      },
      {
        "name": "Mark as Read",
        "type": "button"
      }
    ]
  }
}
```

**Field Descriptions:**
- `id` (required): Unique notification identifier (string)
- `title` (required): Notification title (string)
- `body` (required): Notification body text (string)
- `app` (required): App display name (string)
- `package` (required): App package name (string)
- `actions` (optional): Array of notification actions
  - `name`: Action button text (string)
  - `type`: "button" or "reply" (string)

---

## 8. App Icons

```json
{
  "type": "appIcons",
  "data": {
    "com.whatsapp": {
      "name": "WhatsApp",
      "icon": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
      "systemApp": false,
      "listening": true
    },
    "com.android.chrome": {
      "name": "Chrome",
      "icon": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
      "systemApp": true,
      "listening": true
    }
  }
}
```

**Field Descriptions:**
- Key: Package name (string)
- `name` (required): App display name (string)
- `icon` (required): Base64 encoded PNG icon (string with data URI prefix)
- `systemApp` (required): Whether it's a system app (boolean)
- `listening` (required): Whether notifications are enabled (boolean)

---

## 9. Remote Control (Android Receives)

### Input Tap
```json
{
  "type": "inputEvent",
  "data": {
    "type": "tap",
    "x": 540,
    "y": 1200
  }
}
```

### Input Swipe
```json
{
  "type": "inputEvent",
  "data": {
    "type": "swipe",
    "x1": 540,
    "y1": 1500,
    "x2": 540,
    "y2": 500,
    "durationMs": 200
  }
}
```

### Navigation Action
```json
{
  "type": "navAction",
  "data": {
    "action": "back"
  }
}
```

**Actions:** `"back"`, `"home"`, `"recents"`

### Response from Android
```json
{
  "type": "inputEvent",
  "data": {
    "success": true
  }
}
```

Or on error:
```json
{
  "type": "inputEvent",
  "data": {
    "success": false,
    "error": "Accessibility service not enabled"
  }
}
```

---

## 10. Mirror Control

### Start Mirror Request (Mac → Android)
```json
{
  "type": "mirrorRequest",
  "data": {
    "action": "start",
    "mode": "device",
    "options": {
      "transport": "websocket",
      "fps": 30,
      "maxWidth": 1280,
      "quality": 85,
      "bitrate": 3000000,
      "serverUrl": "ws://192.168.1.100:12345/socket"
    }
  }
}
```

### Mirror Started (Android → Mac)
```json
{
  "type": "mirrorStart",
  "data": {
    "fps": 30,
    "width": 1080,
    "height": 2400,
    "quality": 85
  }
}
```

### Mirror Frame (Android → Mac)
```json
{
  "type": "mirrorFrame",
  "data": {
    "format": "h264",
    "frame": "base64_encoded_h264_data",
    "isConfig": false
  }
}
```

**Field Descriptions:**
- `format`: "h264", "jpeg", or "png"
- `frame`: Base64 encoded frame data
- `isConfig`: True for H.264 SPS/PPS config frames, false for regular frames

### Mirror Stopped (Android → Mac)
```json
{
  "type": "mirrorStop",
  "data": {}
}
```

---

## Common Patterns

### Timestamps
- Always use **milliseconds** since Unix epoch
- JavaScript: `Date.now()`
- Kotlin: `System.currentTimeMillis()`
- Swift: `Date().timeIntervalSince1970 * 1000`

### Null vs Omit
- Use `null` for optional fields with no data
- Or omit the field entirely
- **Never use 0 or empty string** to indicate "no data"

### Contact Names
- Always check address book first
- Use `null` if contact not found
- **Never use empty string** for missing contacts

### Base64 Encoding
- Use standard Base64 encoding
- For images, include data URI prefix: `data:image/png;base64,`
- Or send raw Base64 without prefix (Mac will handle both)

### Error Handling
- Always send response messages
- Include `success: true/false`
- Include `error` field with description on failure

---

## Testing Data Sets

### Complete Health Data (Active Day)
```json
{
  "type": "healthSummary",
  "data": {
    "date": 1735689600000,
    "steps": 12450,
    "distance": 8.7,
    "calories": 2850,
    "activeMinutes": 65,
    "heartRateAvg": 78,
    "heartRateMin": 62,
    "heartRateMax": 152,
    "sleepDuration": 465
  }
}
```

### Minimal Health Data (Lazy Day)
```json
{
  "type": "healthSummary",
  "data": {
    "date": 1735603200000,
    "steps": 2340,
    "distance": 1.5,
    "calories": 1200,
    "activeMinutes": 5,
    "heartRateAvg": null,
    "heartRateMin": null,
    "heartRateMax": null,
    "sleepDuration": 540
  }
}
```

### Sample SMS Threads (5 threads)
```json
{
  "type": "smsThreads",
  "data": {
    "threads": [
      {
        "threadId": "1",
        "address": "+919876543210",
        "contactName": "Mom",
        "messageCount": 342,
        "snippet": "Don't forget to call me tonight!",
        "date": 1735689600000,
        "unreadCount": 2
      },
      {
        "threadId": "2",
        "address": "+919123456789",
        "contactName": "Work - Boss",
        "messageCount": 156,
        "snippet": "Meeting at 3 PM tomorrow",
        "date": 1735686000000,
        "unreadCount": 0
      },
      {
        "threadId": "3",
        "address": "VD-HDFCBK",
        "contactName": null,
        "messageCount": 89,
        "snippet": "Your account balance is Rs 15,234.50",
        "date": 1735682400000,
        "unreadCount": 0
      },
      {
        "threadId": "4",
        "address": "+919988776655",
        "contactName": "Best Friend",
        "messageCount": 1247,
        "snippet": "😂😂😂 That's hilarious!",
        "date": 1735678800000,
        "unreadCount": 5
      },
      {
        "threadId": "5",
        "address": "AM-AMAZON",
        "contactName": null,
        "messageCount": 23,
        "snippet": "Your package will be delivered today",
        "date": 1735675200000,
        "unreadCount": 1
      }
    ]
  }
}
```

### Sample Call Logs (10 calls)
```json
{
  "type": "callLogs",
  "data": {
    "logs": [
      {
        "id": "1",
        "number": "+919876543210",
        "contactName": "Mom",
        "type": "incoming",
        "date": 1735689600000,
        "duration": 245,
        "isRead": true
      },
      {
        "id": "2",
        "number": "+919123456789",
        "contactName": "Work - Boss",
        "type": "outgoing",
        "date": 1735686000000,
        "duration": 180,
        "isRead": true
      },
      {
        "id": "3",
        "number": "+911234567890",
        "contactName": null,
        "type": "missed",
        "date": 1735682400000,
        "duration": 0,
        "isRead": false
      },
      {
        "id": "4",
        "number": "+919988776655",
        "contactName": "Best Friend",
        "type": "incoming",
        "date": 1735678800000,
        "duration": 1245,
        "isRead": true
      },
      {
        "id": "5",
        "number": "+919876543210",
        "contactName": "Mom",
        "type": "outgoing",
        "date": 1735675200000,
        "duration": 67,
        "isRead": true
      },
      {
        "id": "6",
        "number": "+919123456789",
        "contactName": "Work - Boss",
        "type": "missed",
        "date": 1735671600000,
        "duration": 0,
        "isRead": true
      },
      {
        "id": "7",
        "number": "+919988776655",
        "contactName": "Best Friend",
        "type": "incoming",
        "date": 1735668000000,
        "duration": 892,
        "isRead": true
      },
      {
        "id": "8",
        "number": "+911234567890",
        "contactName": null,
        "type": "outgoing",
        "date": 1735664400000,
        "duration": 34,
        "isRead": true
      },
      {
        "id": "9",
        "number": "+919876543210",
        "contactName": "Mom",
        "type": "incoming",
        "date": 1735660800000,
        "duration": 456,
        "isRead": true
      },
      {
        "id": "10",
        "number": "+919988776655",
        "contactName": "Best Friend",
        "type": "rejected",
        "date": 1735657200000,
        "duration": 0,
        "isRead": true
      }
    ]
  }
}
```

---

## Quick Reference

### Message Types
| Type | Direction | Purpose |
|------|-----------|---------|
| `healthSummary` | Android → Mac | Send health data |
| `smsThreads` | Android → Mac | Send SMS thread list |
| `callLogs` | Android → Mac | Send call log list |
| `callNotification` | Android → Mac | Live call updates |
| `smsReceived` | Android → Mac | New SMS received |
| `status` | Android → Mac | Device status update |
| `notification` | Android → Mac | App notification |
| `inputEvent` | Mac → Android | Touch/swipe command |
| `navAction` | Mac → Android | Navigation command |
| `mirrorRequest` | Mac → Android | Start/stop mirror |
| `mirrorStart` | Android → Mac | Mirror started |
| `mirrorFrame` | Android → Mac | Video frame |
| `mirrorStop` | Android → Mac | Mirror stopped |

### Data Types
- **Timestamps**: Integer (milliseconds since Unix epoch)
- **Phone Numbers**: String (with country code)
- **Contact Names**: String or `null`
- **Durations**: Integer (seconds or minutes as specified)
- **Percentages**: Integer (0-100)
- **Booleans**: `true` or `false`
- **Base64**: String (with or without data URI prefix)

---

**Last Updated:** December 31, 2024  
**Version:** 2.0
