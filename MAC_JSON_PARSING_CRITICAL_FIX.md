# 🔴 CRITICAL FIX: Mac JSON Parsing Issue

## Problem
The Mac client had a critical JSON parsing bug that was breaking all data communication:
- Used Codable which fails on dynamic JSON structures
- Returned empty dictionaries `[:]` for all data
- Affected health data, SMS threads, and call logs
- Android was sending perfect JSON, but Mac couldn't parse it

## Root Cause
The issue was in `WebSocketServer.swift` where it used:
```swift
let message = try JSONDecoder().decode(Message.self, from: data)
```

This relied on the `CodableValue` struct in `AnyDecodable.swift` which tried to decode JSON into specific Swift types. When Android sent dynamic JSON structures, the Codable system failed and fell back to empty dictionaries.

## Solution Applied
Replaced Codable parsing with flexible JSONSerialization approach:

### 1. Updated WebSocketServer.swift
- Replaced `JSONDecoder().decode(Message.self, from: data)` with `JSONSerialization.jsonObject`
- Added manual type and data extraction
- Created new `handleFlexibleMessage` method for critical message types

### 2. Added FlexibleMessage struct
```swift
struct FlexibleMessage {
    let type: MessageType
    let data: [String: Any]
}
```

### 3. Implemented Flexible Parsing
- **SMS Threads**: Direct dictionary parsing with proper type conversion
- **Call Logs**: Direct dictionary parsing with proper type conversion  
- **Health Data**: Direct dictionary parsing with proper type conversion
- **Device Info**: Direct dictionary parsing
- **Status Updates**: Direct dictionary parsing

## Key Improvements

### Before (Broken)
```swift
// This would fail and return [:]
if let dict = message.data.value as? [String: Any] {
    // dict was always empty due to Codable failure
}
```

### After (Fixed)
```swift
// Direct JSONSerialization parsing
guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    print("[websocket] Failed to parse JSON as dictionary")
    return
}

let messageData = jsonObject["data"] as? [String: Any] ?? [:]
print("[websocket] ✅ Parsed JSON - type: \(typeString), data keys: \(messageData.keys.joined(separator: ", "))")
```

## Files Modified
1. `airsync-mac/Core/WebSocket/WebSocketServer.swift`
   - Updated JSON parsing logic
   - Added `handleFlexibleMessage` method
   - Added detailed logging for debugging

2. `airsync-mac/Model/Message.swift`
   - Added `FlexibleMessage` struct

## Testing Results
- ✅ SMS threads now parse correctly
- ✅ Call logs now parse correctly  
- ✅ Health data now parses correctly
- ✅ Device info now parses correctly
- ✅ All other message types still work via fallback

## Backward Compatibility
The fix maintains backward compatibility by:
- Keeping the original `Message` and `CodableValue` structs
- Using `handleFlexibleMessage` for critical types only
- Falling back to original `handleMessage` for other types

## Performance Impact
- **Positive**: JSONSerialization is faster than Codable for dynamic JSON
- **Positive**: Reduced memory allocation from failed Codable attempts
- **Positive**: Better error handling and logging

## Monitoring
Added comprehensive logging to track parsing success:
```
[websocket] ✅ Parsed JSON - type: smsThreads, data keys: threads
[websocket] 📱 Processing 5 SMS threads
[websocket] 📱 Successfully parsed 5 SMS threads
```

This fix resolves the critical JSON parsing issue that was preventing all data communication between Android and Mac clients.