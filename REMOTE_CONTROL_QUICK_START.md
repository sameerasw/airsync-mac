# Remote Control Quick Start Guide

## 🚀 Quick Setup (5 Minutes)

### Step 1: Enable Accessibility Service (Android)
1. Open **Settings** → **Accessibility**
2. Find **"AirSync Remote Control"**
3. Toggle **ON**
4. Tap **Allow** on permission dialog

### Step 2: Start Mirroring (Mac)
1. Open **AirSync** on Mac
2. Connect Android device (scan QR code)
3. Click **"Start Mirror"** button
4. Wait for mirror window to appear (~2 seconds)

### Step 3: Test Remote Control
- **Click** anywhere → Taps on Android
- **Click & Drag** → Swipes on Android
- **Scroll** with trackpad/mouse → Scrolls on Android
- **Delete/Backspace** → Back button
- **Escape** → Home button

## ✅ Verification Checklist

### Before Starting
- [ ] Android is on same WiFi as Mac
- [ ] Accessibility service is enabled
- [ ] Screen capture permission granted
- [ ] AirSync app is connected

### After Starting Mirror
- [ ] Mirror window opens within 2 seconds
- [ ] Video is smooth (no stuttering)
- [ ] Taps register where you click
- [ ] Swipes feel natural
- [ ] Scrolling is smooth
- [ ] Navigation buttons work

## 🎯 Quick Tests

### Test 1: Tap Accuracy
1. Open Android home screen
2. Click on an app icon in mirror
3. **Expected**: App opens on Android
4. **Pass**: ✅ App opens correctly

### Test 2: Swipe Gesture
1. Open app drawer or long list
2. Click and drag up/down in mirror
3. **Expected**: List scrolls smoothly
4. **Pass**: ✅ Scrolling is smooth

### Test 3: Navigation
1. Open any app
2. Press **Delete** key on Mac
3. **Expected**: Goes back on Android
4. **Pass**: ✅ Back navigation works

### Test 4: Scroll Wheel
1. Open a web page or long document
2. Use trackpad/mouse wheel to scroll
3. **Expected**: Page scrolls on Android
4. **Pass**: ✅ Scrolling works

## 🐛 Quick Fixes

### Problem: Taps are off by a few pixels
**Fix**: Already handled automatically - Mac uses actual frame dimensions

### Problem: High latency (> 300ms)
**Quick Fix**:
1. Switch to 5GHz WiFi
2. Move closer to router
3. Close other apps using network

### Problem: Accessibility service not working
**Quick Fix**:
1. Settings → Accessibility
2. Toggle service OFF then ON
3. Restart AirSync app

### Problem: Mirror won't start
**Quick Fix**:
1. Check Android logs: `adb logcat | grep Mirror`
2. Verify screen capture permission
3. Restart both apps

## 📊 Performance Targets

| Metric | Target | Good | Acceptable |
|--------|--------|------|------------|
| Latency | < 150ms | < 200ms | < 300ms |
| FPS | 30 | 25-30 | 20-25 |
| Touch Response | < 50ms | < 100ms | < 150ms |
| Bitrate | 3 Mbps | 2-4 Mbps | 1-5 Mbps |

## 🎮 Usage Tips

### For Best Performance
- Use **5GHz WiFi** (not 2.4GHz)
- Keep devices **close to router**
- Close **other network apps**
- Use **720p resolution** (1280px)

### For Best Quality
- Use **wired connection** if possible
- Increase **bitrate to 4-5 Mbps**
- Use **1080p resolution** (1920px)
- Ensure **strong WiFi signal**

### For Gaming/Low Latency
- Use **540p resolution** (960px)
- Keep **bitrate at 2 Mbps**
- Use **30 FPS** (not 60)
- Minimize **network traffic**

## 🔧 Advanced Settings

### Adjust Mirror Quality (Mac)
```swift
// In AppState or settings
AppState.shared.mirrorFPS = 30          // Frame rate
AppState.shared.mirrorMaxWidth = 1280   // Resolution
AppState.shared.mirrorQuality = 85      // H.264 quality
AppState.shared.mirrorBitrate = 3000000 // 3 Mbps
```

### Adjust Encoder (Android)
```kotlin
// In MirroringOptions
MirroringOptions(
    maxWidth = 1280,      // 720p, 1080p, or 540p
    fps = 30,             // 30 or 60
    bitrateKbps = 3000    // 2000-5000
)
```

## 📱 Supported Gestures

| Gesture | Mac Input | Android Action |
|---------|-----------|----------------|
| Tap | Click | Tap |
| Long Press | Hold click (future) | Long press |
| Swipe | Click & drag | Swipe |
| Scroll | Trackpad/wheel | Scroll |
| Back | Delete/Backspace | Back button |
| Home | Escape | Home button |
| Recents | Button | Recent apps |

## 🎯 Success Criteria

Your setup is working perfectly when:
1. ✅ Mirror starts in < 2 seconds
2. ✅ Video is smooth and clear
3. ✅ Taps are accurate (< 5px error)
4. ✅ Swipes feel natural
5. ✅ Scrolling is smooth
6. ✅ Latency is imperceptible
7. ✅ No errors in logs

## 📞 Need Help?

### Check Logs

**Mac (Xcode Console):**
```
Look for: [remote-control], [mirror], [websocket]
```

**Android (ADB):**
```bash
adb logcat | grep -E "RemoteInputHandler|Mirror|WebSocket"
```

### Common Log Messages

**Success:**
```
[remote-control] ✅ TAP event sent to Android
[mirror] ✅ Mirror started successfully
```

**Errors:**
```
[remote-control] ❌ Input event failed on Android
[mirror] ⏱️ Mirror request timed out
```

## 🎉 You're Done!

If all tests pass, your remote control is working perfectly. Enjoy controlling your Android device from your Mac!

**Pro Tip**: Use keyboard shortcuts (Delete for Back, Escape for Home) for faster navigation.
