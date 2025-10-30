# Remote Control Verification Checklist

## Pre-Flight Checks

### Android Setup
- [ ] Android 7.0+ (Nougat or higher)
- [ ] AirSync app installed and updated
- [ ] Connected to same WiFi as Mac
- [ ] Screen capture permission granted
- [ ] Accessibility service enabled (Settings → Accessibility → AirSync)

### Mac Setup
- [ ] AirSync app running
- [ ] WebSocket server started
- [ ] Device connected (QR code scanned)
- [ ] No firewall blocking port 12345

## Build Verification

### Android Build
- [ ] No build errors in Android Studio
- [ ] `SimpleHealthScreen.kt` compiles
- [ ] `RemoteInputHandler.kt` exists
- [ ] `RemoteControlReceiver.kt` exists
- [ ] `accessibility_service_config.xml` exists

### Mac Build
- [ ] No build errors in Xcode
- [ ] `InteractiveMirrorView.swift` compiles
- [ ] `MirrorPerformanceOverlay.swift` compiles
- [ ] `WebSocketServer.swift` has remote control methods

## Functional Testing

### 1. Mirror Start Test
- [ ] Click "Start Mirror" button on Mac
- [ ] Mirror window opens within 2 seconds
- [ ] Video stream appears (not black screen)
- [ ] Video is smooth (no stuttering)
- [ ] Performance overlay shows FPS > 25

**Expected**: Mirror starts quickly with smooth video

### 2. Tap Test
- [ ] Open Android home screen
- [ ] Click on an app icon in mirror window
- [ ] App opens on Android device
- [ ] Tap location is accurate (< 5px error)

**Expected**: Taps register exactly where you click

### 3. Swipe Test
- [ ] Open app drawer or long list
- [ ] Click and drag up/down in mirror
- [ ] List scrolls smoothly on Android
- [ ] Swipe feels natural (not too fast/slow)

**Expected**: Swipes are smooth and responsive

### 4. Scroll Test
- [ ] Open web browser or long document
- [ ] Use trackpad/mouse wheel to scroll
- [ ] Content scrolls on Android
- [ ] Scroll direction is correct (up = up)

**Expected**: Scrolling works with trackpad/wheel

### 5. Navigation Test
- [ ] Open any app on Android
- [ ] Press **Delete/Backspace** on Mac keyboard
- [ ] Android goes back
- [ ] Press **Escape** on Mac keyboard
- [ ] Android goes to home screen
- [ ] Click **Recents** button in mirror
- [ ] Recent apps screen appears

**Expected**: All navigation methods work

### 6. Performance Test
- [ ] Click chart icon to show performance overlay
- [ ] FPS is green (28-30)
- [ ] Latency is green (< 150ms) or orange (< 250ms)
- [ ] Dropped frames is 0 or very low
- [ ] Video remains smooth during interaction

**Expected**: Good performance metrics

## Performance Benchmarks

### Excellent Performance ✅
- FPS: 28-30 (green)
- Latency: < 150ms (green)
- Dropped Frames: 0
- Touch Response: < 50ms

### Good Performance ✓
- FPS: 25-28 (orange)
- Latency: 150-250ms (orange)
- Dropped Frames: < 5
- Touch Response: 50-100ms

### Poor Performance ⚠️
- FPS: < 25 (red)
- Latency: > 250ms (red)
- Dropped Frames: > 10
- Touch Response: > 100ms

## Troubleshooting Checks

### If Mirror Won't Start
- [ ] Check Android logs: `adb logcat | grep Mirror`
- [ ] Verify screen capture permission
- [ ] Check WebSocket connection status
- [ ] Restart both apps
- [ ] Check network connectivity

### If Touch Not Working
- [ ] Verify accessibility service is enabled
- [ ] Check Android logs: `adb logcat | grep RemoteInputHandler`
- [ ] Restart accessibility service
- [ ] Check Android version (7.0+)
- [ ] Grant all permissions

### If High Latency
- [ ] Switch to 5GHz WiFi
- [ ] Move closer to router
- [ ] Close other network apps
- [ ] Reduce resolution to 720p
- [ ] Lower FPS to 30
- [ ] Check network ping: `ping <android-ip>`

### If Coordinates Off
- [ ] Check performance overlay shows frames
- [ ] Verify Android screen resolution
- [ ] Check Mac logs for coordinate mapping
- [ ] Restart mirror session
- [ ] Update to latest version

## Log Verification

### Mac Logs (Xcode Console)
Look for these success messages:
```
[remote-control] ✅ TAP event sent to Android
[remote-control] ✅ SWIPE event sent to Android
[remote-control] ✅ NAV ACTION sent to Android
[mirror] ✅ Mirror started successfully
```

### Android Logs (ADB)
```bash
adb logcat | grep -E "RemoteInputHandler|Mirror|WebSocket"
```

Look for:
```
RemoteInputHandler: Performing tap at (x, y)
RemoteInputHandler: Performing swipe from (x1, y1) to (x2, y2)
Mirror: Started successfully
```

## Final Verification

### All Systems Go ✅
- [ ] Mirror starts in < 2 seconds
- [ ] Video is smooth and clear
- [ ] Taps are accurate
- [ ] Swipes feel natural
- [ ] Scrolling is smooth
- [ ] Navigation works
- [ ] Performance is good
- [ ] No errors in logs

### Ready for Production
- [ ] All functional tests pass
- [ ] Performance benchmarks met
- [ ] No critical errors
- [ ] Documentation complete
- [ ] User guide available

## Sign-Off

**Tested By**: _________________

**Date**: _________________

**Result**: ☐ Pass  ☐ Fail  ☐ Needs Work

**Notes**:
_________________________________________________
_________________________________________________
_________________________________________________

## Quick Reference

### Keyboard Shortcuts
- **Delete/Backspace**: Back
- **Escape**: Home
- **Chart Icon**: Toggle performance overlay

### Performance Targets
- **FPS**: 28-30
- **Latency**: < 150ms
- **Touch Response**: < 50ms

### Optimal Settings
- **Resolution**: 1280px (720p)
- **FPS**: 30
- **Bitrate**: 3 Mbps
- **Network**: 5GHz WiFi

---

**Status**: Ready for Testing
**Version**: 2.0.0+
**Last Updated**: 2025-10-29
