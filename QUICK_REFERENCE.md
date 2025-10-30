# AirSync Remote Control - Quick Reference Card

## 🎮 Controls

| Action | Mac Input | Result |
|--------|-----------|--------|
| **Tap** | Click | Tap on Android |
| **Swipe** | Click + Drag | Swipe on Android |
| **Scroll** | Mouse Wheel / Trackpad | Scroll on Android |
| **Back** | Delete / Backspace | Back button |
| **Home** | Escape | Home screen |
| **Recents** | Button (bottom) | Recent apps |
| **Stats** | Chart icon (top-right) | Show/hide performance |

## 🚀 Quick Start

1. **Android**: Settings → Accessibility → AirSync → ON
2. **Mac**: Open AirSync → Connect → Start Mirror
3. **Use**: Click, drag, scroll on mirror window

## 📊 Performance Indicators

| Color | FPS | Latency | Status |
|-------|-----|---------|--------|
| 🟢 Green | >28 | <150ms | Optimal |
| 🟠 Orange | 20-28 | 150-250ms | Good |
| 🔴 Red | <20 | >250ms | Poor |

## ⚡ Optimization Tips

### Low Latency
- Use 5GHz WiFi
- Resolution: 960px (540p)
- Bitrate: 2 Mbps
- FPS: 30

### Balanced (Recommended)
- Use 5GHz WiFi
- Resolution: 1280px (720p)
- Bitrate: 3 Mbps
- FPS: 30

### High Quality
- Use wired/5GHz WiFi
- Resolution: 1920px (1080p)
- Bitrate: 5 Mbps
- FPS: 30

## 🐛 Quick Fixes

| Problem | Solution |
|---------|----------|
| High latency | Switch to 5GHz WiFi, reduce resolution |
| Taps off | Already fixed - uses actual dimensions |
| No touch | Enable accessibility service |
| Choppy video | Reduce resolution to 720p |
| Won't start | Check screen capture permission |

## 📱 Requirements

- **Android**: 7.0+ (Nougat or higher)
- **Mac**: macOS 12+ (Monterey or higher)
- **Network**: Same WiFi network
- **Permissions**: Accessibility + Screen capture

## 🔧 Troubleshooting Commands

```bash
# Check Android logs
adb logcat | grep -E "RemoteInputHandler|Mirror"

# Check accessibility service
adb shell settings get secure enabled_accessibility_services

# Test network latency
ping <android_ip>
```

## 📞 Support

- Check logs for [remote-control] and [mirror] messages
- Verify accessibility service is enabled
- Ensure both devices on same network
- Try restarting both apps

## ✅ Success Checklist

- [ ] Mirror opens in < 2 seconds
- [ ] FPS shows 28-30 (green)
- [ ] Latency < 200ms (green/orange)
- [ ] Taps register accurately
- [ ] Swipes feel natural
- [ ] Scrolling is smooth

---

**Version:** 1.0 | **Updated:** 2024
