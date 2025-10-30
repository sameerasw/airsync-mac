# Remote Control Implementation

## Overview
Implemented bidirectional remote control functionality for AirSync, allowing Mac users to control their Android device through the mirrored screen.

## Features Implemented

### 1. Interactive Mirror View (`InteractiveMirrorView.swift`)
- **Touch/Click Events**: Click anywhere on the mirrored screen to tap on Android
- **Drag/Swipe Gestures**: Click and drag to perform swipe gestures
- **Scroll Support**: Use mouse wheel/trackpad to scroll on Android
- **Coordinate Mapping**: Automatically converts Mac coordinates to Android coordinates

### 2. Navigation Controls
- **Back Button**: Navigate back (also mapped to Delete/Backspace key)
- **Home Button**: Go to home screen (also mapped to Escape key)
- **Recent Apps**: View recent apps
- **Auto-hide Controls**: Controls appear on hover for clean viewing

### 3. Input Event System
Using existing WebSocket message handlers:
- `sendInputTap(x, y)`: Sends tap events to Android
- `sendInputSwipe(x1, y1, x2, y2, durationMs)`: Sends swipe gestures
- `sendNavAction(action)`: Sends navigation commands (back, home, recents)
- `sendInputKey(keyCode)`: Sends key events
- `sendInputText(text)`: Sends text input

### 4. Quality Improvements
Enhanced video streaming quality with configurable settings:
- **FPS**: 60 fps (up from 30) for smoother experience
- **Resolution**: 1920px max width (up from 1280) for sharper image
- **Quality**: 85% H.264 quality
- **Bitrate**: 8 Mbps for better video quality

### 5. User-Configurable Settings
Added to AppState:
- `mirrorFPS`: Frame rate (default: 60)
- `mirrorMaxWidth`: Maximum resolution width (default: 1920)
- `mirrorQuality`: H.264 quality 0-100 (default: 85)
- `mirrorBitrate`: Video bitrate in bps (default: 8000000)

## Android Side Requirements

For full functionality, the Android app needs to implement:

### 1. Input Event Handler
```kotlin
when (message.type) {
    "inputEvent" -> {
        val type = data.getString("type") // "tap", "swipe", "key", "text"
        
        when (type) {
            "tap" -> {
                val x = data.getInt("x") // Pixel coordinates
                val y = data.getInt("y")
                performTap(x, y)
            }
            "swipe" -> {
                val x1 = data.getInt("x1")
                val y1 = data.getInt("y1")
                val x2 = data.getInt("x2")
                val y2 = data.getInt("y2")
                val durationMs = data.getInt("durationMs")
                performSwipe(x1, y1, x2, y2, durationMs)
            }
            "key" -> {
                val keyCode = data.getInt("keyCode")
                performKeyPress(keyCode)
            }
            "text" -> {
                val text = data.getString("text")
                performTextInput(text)
            }
        }
    }
}
```

### 2. Navigation Actions
```kotlin
when (message.type) {
    "navAction" -> {
        val action = data.getString("action")
        when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        }
    }
}
```

### 3. Accessibility Service
The Android app needs accessibility permissions to:
- Inject touch events using `dispatchGesture()`
- Perform global navigation actions
- Control the device programmatically

### 4. Video Encoder Settings
Update the H.264 encoder to use the quality parameters:
```kotlin
val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate) // From Mac
format.setInteger(MediaFormat.KEY_FRAME_RATE, fps) // From Mac
format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
format.setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
```

## Usage

### For Users
1. Start mirroring from the Mac app
2. The mirror window will open with your Android screen
3. Click anywhere to tap on Android
4. Click and drag to swipe
5. Use mouse wheel to scroll
6. Use navigation buttons at the bottom or keyboard shortcuts:
   - **Delete/Backspace**: Back
   - **Escape**: Home

### For Developers
To adjust quality settings programmatically:
```swift
AppState.shared.mirrorFPS = 30 // Lower for slower connections
AppState.shared.mirrorMaxWidth = 1280 // Lower for bandwidth savings
AppState.shared.mirrorQuality = 70 // Lower for faster encoding
AppState.shared.mirrorBitrate = 4000000 // 4 Mbps for slower networks
```

## Troubleshooting

### Blurry/Glitchy Video
- **Cause**: Network bandwidth or Android encoder limitations
- **Solution**: 
  - Reduce `mirrorMaxWidth` to 1280 or 720
  - Lower `mirrorFPS` to 30
  - Reduce `mirrorBitrate` to 4000000 (4 Mbps)

### High Latency
- **Cause**: Network latency or processing overhead
- **Solution**:
  - Ensure both devices are on same WiFi network (not mobile data)
  - Reduce FPS and resolution
  - Use 5GHz WiFi instead of 2.4GHz
  - Close other network-intensive apps

### Touch Events Not Working
- **Cause**: Android app doesn't have accessibility permissions
- **Solution**: 
  - Go to Android Settings > Accessibility
  - Enable AirSync accessibility service
  - Grant all required permissions

## Next Steps

1. **Android Implementation**: Implement the input event handlers on Android side
2. **Performance Optimization**: Add adaptive bitrate based on network conditions
3. **Gesture Recognition**: Add support for multi-touch gestures (pinch, zoom)
4. **Keyboard Input**: Forward keyboard input from Mac to Android
5. **Quality Presets**: Add preset buttons (Low/Medium/High/Ultra quality)
