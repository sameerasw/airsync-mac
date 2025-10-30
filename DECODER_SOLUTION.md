# Decoder Solution - Automatic Fallback

## Problem Identified

VideoToolbox is rejecting the H.264 stream with error `-12712` (kVTParameterErr).

**SPS Analysis:**
```
67 42 80 1F = H.264 High Profile, Level 3.1
```

VideoToolbox on some Macs has compatibility issues with certain H.264 profiles/levels from Android encoders.

## Solution Implemented

**Automatic Fallback System:**
1. Try VideoToolbox first (hardware, fast)
2. If it fails, automatically fall back to FFmpeg (software, slower but works)

## How It Works

```swift
// Start with VideoToolbox
[H264Decoder] ⚡ Attempting native VideoToolbox hardware decoder

// If VideoToolbox fails:
[H264Decoder] ❌ Failed to create format description: -12712
[H264Decoder] 🔄 Falling back to FFmpeg software decoder

// Continue with FFmpeg
[H264Decoder] Using FFmpeg software decoder backend
```

## Expected Behavior

**Best Case (VideoToolbox works):**
- FPS: 28-30
- Latency: 100-150ms
- CPU: 10-20%

**Fallback Case (FFmpeg):**
- FPS: 20-25 (better than before due to optimizations)
- Latency: 150-250ms
- CPU: 30-40%

## Android Fix (Recommended)

To make VideoToolbox work, Android should use **Baseline Profile**:

```kotlin
format.setInteger(
    MediaFormat.KEY_PROFILE,
    MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline
)
```

This is more compatible and VideoToolbox will work.

## Summary

- ✅ Automatic fallback implemented
- ✅ App won't crash if VideoToolbox fails
- ✅ Will use FFmpeg as backup
- ⚠️ Performance will be lower with FFmpeg
- 💡 Android should switch to Baseline profile for best results

Rebuild and test - it should work now!
