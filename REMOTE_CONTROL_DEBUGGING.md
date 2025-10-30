# Remote Control Debugging Guide

## 🔍 Detailed Logging Added

### Mac Side Logs

All remote control actions now have detailed logging with emojis for easy identification:

#### Input Events
```
[remote-control] 📍 Sending TAP: x=500, y=800
[remote-control] 📤 Sending inputEvent: {"type":"inputEvent","data":{"type":"tap","x":500,"y":800}}
[remote-control] ✅ TAP event sent to Android
```

#### Swipe Events
```
[remote-control] 👆 Sending SWIPE: (500,1000) → (500,300) duration=200ms
[remote-control] 📤 Sending inputEvent: {"type":"inputEvent","data":{"type":"swipe",...}}
[remote-control] ✅ SWIPE event sent to Android
```

#### Navigation Actions
```
[remote-control] 🧭 Sending NAV ACTION: back
[remote-control] 📤 Sending navAction: {"type":"navAction","data":{"action":"back"}}
[remote-control] ✅ NAV ACTION sent to Android
```

#### Responses from Android
```
[remote-control] 📥 Received inputEvent response from Android: {"success":true}
[remote-control] ✅ Input event processed successfully on Android
```

Or if failed:
```
[remote-control] 📥 Received inputEvent response from Android: {"success":false,"error":"..."}
[remote-control] ❌ Input event failed on Android: Accessibility service not enabled
```

### Mirror Logs

#### Starting Mirror
```
[mirror] 🎬 Starting mirror request...
[mirror] 📤 Sending mirror request with options: fps=60, maxWidth=1920
```

#### Mirror Started
```
[mirror] 📥 Received mirrorStart from Android
[mirror] 📊 Mirror parameters: fps=60 quality=85 width=1920 height=nil
[mirror] ✅ Mirror started successfully -> presenting UI now
```

#### Mirror Stopped
```
[mirror] 🛑 Received mirrorStop from Android
[mirror] ✅ Mirror stopped successfully
```

#### Mirror Timeout
```
[mirror] ⏱️ Mirror request timed out - no response from Android
```

## 🐛 Debugging Steps

### Step 1: Check Mac Logs

Run your Mac app and watch the console for these log prefixes:
- `[remote-control]` - All remote control events
- `[mirror]` - Mirror state changes
- `[websocket]` - WebSocket communication

### Step 2: Check Android Logs

```bash
# Filter for remote control logs
adb logcat | grep -E "InputAccessibilityService|WebSocketMessageHandler|inputEvent|navAction"

# Or more specific
adb logcat -s InputAccessibilityService WebSocketMessageHandler
```

### Step 3: Verify Message Flow

#### Expected Flow for TAP:
1. **Mac:** `[remote-control] 📍 Sending TAP: x=500, y=800`
2. **Mac:** `[remote-control] 📤 Sending inputEvent: {...}`
3. **Mac:** `[remote-control] ✅ TAP event sent to Android`
4. **Android:** `WebSocketMessageHandler: Received inputEvent`
5. **Android:** `InputAccessibilityService: Performing tap at (500, 800)`
6. **Android:** `InputAccessibilityService: Tap gesture dispatched successfully`
7. **Mac:** `[remote-control] 📥 Received inputEvent response from Android: {"success":true}`
8. **Mac:** `[remote-control] ✅ Input event processed successfully on Android`

#### Expected Flow for NAV ACTION:
1. **Mac:** `[remote-control] 🧭 Sending NAV ACTION: back`
2. **Mac:** `[remote-control] 📤 Sending navAction: {...}`
3. **Mac:** `[remote-control] ✅ NAV ACTION sent to Android`
4. **Android:** `WebSocketMessageHandler: Received navAction`
5. **Android:** `InputAccessibilityService: Performing global action: BACK`
6. **Android:** `InputAccessibilityService: Global action performed successfully`
7. **Mac:** `[remote-control] 📥 Received navAction response from Android: {"success":true}`
8. **Mac:** `[remote-control] ✅ Nav action processed successfully on Android`

## 🔧 Common Issues

### Issue 1: No Response from Android

**Symptoms:**
- Mac logs show: `[remote-control] ✅ TAP event sent to Android`
- But no response: `[remote-control] 📥 Received inputEvent response...`

**Possible Causes:**
1. Android app not receiving messages
2. WebSocket connection broken
3. Android not sending responses

**Debug:**
```bash
# Check Android logs
adb logcat | grep "WebSocketMessageHandler"

# Should see:
# WebSocketMessageHandler: Received message: {"type":"inputEvent",...}
```

**Fix:**
- Check WebSocket connection status
- Restart Android app
- Check Android permissions

### Issue 2: Android Receives but Doesn't Process

**Symptoms:**
- Android logs show: `WebSocketMessageHandler: Received inputEvent`
- But no: `InputAccessibilityService: Performing tap...`

**Possible Causes:**
1. Accessibility Service not enabled
2. Accessibility Service not running
3. Message parsing error

**Debug:**
```bash
# Check if accessibility service is enabled
adb shell settings get secure enabled_accessibility_services

# Should include: com.sameerasw.airsync/.service.InputAccessibilityService
```

**Fix:**
1. Go to Android Settings → Accessibility
2. Find AirSync
3. Enable the accessibility service
4. Grant all permissions

### Issue 3: Tap Coordinates Wrong

**Symptoms:**
- Tap works but hits wrong location
- Coordinates seem off

**Possible Causes:**
1. Screen resolution mismatch
2. Coordinate scaling issue
3. Y-axis inversion

**Debug:**
```swift
// In InteractiveMirrorView.swift, add logging:
private func handleTap(at point: CGPoint, in imageSize: CGSize) {
    print("[remote-control] 🖱️ Mac tap at: \(point) in image size: \(imageSize)")
    
    let androidX = Int(point.x * scaleX)
    let androidY = Int(point.y * scaleY)
    
    print("[remote-control] 📱 Android coordinates: (\(androidX), \(androidY))")
    print("[remote-control] 📐 Scale factors: x=\(scaleX), y=\(scaleY)")
    
    WebSocketServer.shared.sendInputTap(x: androidX, y: androidY)
}
```

**Fix:**
- Adjust `androidWidth` and `androidHeight` in `InteractiveMirrorView.swift`
- Check if Y-axis needs inversion
- Verify image aspect ratio matches Android screen

### Issue 4: Mirror Not Starting

**Symptoms:**
- Click "Start Mirror" button
- Nothing happens or button stays disabled

**Debug:**
```
# Mac logs should show:
[mirror] 🎬 Starting mirror request...
[mirror] 📤 Sending mirror request with options: fps=60, maxWidth=1920

# Then either:
[mirror] 📥 Received mirrorStart from Android
[mirror] ✅ Mirror started successfully

# Or:
[mirror] ⏱️ Mirror request timed out - no response from Android
```

**Possible Causes:**
1. Android doesn't have screen capture permission
2. Android encoder failed to start
3. Network issue

**Fix:**
1. Grant screen capture permission on Android
2. Check Android logs for encoder errors
3. Restart both apps

## 📊 Log Analysis

### Successful Remote Control Session

```
[remote-control] 📍 Sending TAP: x=540, y=1170
[remote-control] 📤 Sending inputEvent: {"type":"inputEvent","data":{"type":"tap","x":540,"y":1170}}
[remote-control] ✅ TAP event sent to Android
[remote-control] 📥 Received inputEvent response from Android: {"success":true}
[remote-control] ✅ Input event processed successfully on Android

[remote-control] 👆 Sending SWIPE: (540,1500) → (540,500) duration=200ms
[remote-control] 📤 Sending inputEvent: {"type":"inputEvent","data":{"type":"swipe",...}}
[remote-control] ✅ SWIPE event sent to Android
[remote-control] 📥 Received inputEvent response from Android: {"success":true}
[remote-control] ✅ Input event processed successfully on Android

[remote-control] 🧭 Sending NAV ACTION: back
[remote-control] 📤 Sending navAction: {"type":"navAction","data":{"action":"back"}}
[remote-control] ✅ NAV ACTION sent to Android
[remote-control] 📥 Received navAction response from Android: {"success":true}
[remote-control] ✅ Nav action processed successfully on Android
```

### Failed Remote Control (Accessibility Not Enabled)

```
[remote-control] 📍 Sending TAP: x=540, y=1170
[remote-control] 📤 Sending inputEvent: {"type":"inputEvent","data":{"type":"tap","x":540,"y":1170}}
[remote-control] ✅ TAP event sent to Android
[remote-control] 📥 Received inputEvent response from Android: {"success":false,"error":"Accessibility service not enabled"}
[remote-control] ❌ Input event failed on Android: Accessibility service not enabled
```

## 🎯 Quick Checklist

### Mac Side
- [ ] WebSocket connected
- [ ] Mirror window open
- [ ] Clicking on mirror view
- [ ] Seeing `[remote-control]` logs
- [ ] Seeing "sent to Android" messages

### Android Side
- [ ] App running and connected
- [ ] Accessibility Service enabled
- [ ] Screen capture permission granted
- [ ] Seeing `WebSocketMessageHandler` logs
- [ ] Seeing `InputAccessibilityService` logs

### Network
- [ ] Both devices on same WiFi
- [ ] No firewall blocking
- [ ] WebSocket connection stable
- [ ] Messages flowing both ways

## 📞 Support

If remote control still doesn't work after checking all above:

1. **Capture full logs:**
   ```bash
   # Mac: Copy all console output with [remote-control] prefix
   # Android:
   adb logcat -s InputAccessibilityService WebSocketMessageHandler > android_logs.txt
   ```

2. **Check message format:**
   - Verify JSON structure matches expected format
   - Check for encoding issues
   - Verify data types (Int vs String)

3. **Test with simple command:**
   ```swift
   // Try sending a simple back command
   WebSocketServer.shared.sendNavAction("back")
   
   // Watch logs for full flow
   ```

4. **Verify Android implementation:**
   - Check `InputAccessibilityService` is properly handling events
   - Verify `dispatchGesture()` is being called
   - Check for Android API level restrictions

## 🎉 Success Indicators

You'll know remote control is working when you see:

1. **Mac logs show complete flow:**
   - Sending event
   - Event sent
   - Response received
   - Success confirmed

2. **Android responds to actions:**
   - Taps open apps
   - Swipes scroll content
   - Back button navigates back
   - Home button goes home

3. **No error messages in logs**

4. **Smooth, responsive interaction**
