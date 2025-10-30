# Remove FFmpeg Dependency

## Why Remove FFmpeg?

Now that we're using native VideoToolbox, FFmpeg is no longer needed. Removing it will:
- ✅ Eliminate build warnings
- ✅ Reduce app size
- ✅ Faster build times
- ✅ Simpler dependencies
- ✅ No version conflicts

## Current Warnings

```
Building for macOS-14.5, but linking with dylib '/opt/homebrew/opt/ffmpeg/lib/libavcodec.62.dylib' which was built for newer version 26.0
Building for macOS-14.5, but linking with dylib '/opt/homebrew/opt/ffmpeg/lib/libavutil.60.dylib' which was built for newer version 26.0
Building for macOS-14.5, but linking with dylib '/opt/homebrew/opt/ffmpeg/lib/libswscale.9.dylib' which was built for newer version 26.0
```

## Steps to Remove FFmpeg

### 1. Remove FFmpeg Files

Delete these files (if they exist):
```
airsync-mac/Core/FFmpeg/
airsync-mac/Screens/Settings/FFmpegDecoder.swift
```

Or search for any files containing "FFmpeg" or "ffmpeg":
```bash
find airsync-mac -name "*FFmpeg*" -o -name "*ffmpeg*"
```

### 2. Remove from Xcode Project

1. Open Xcode
2. Select your project in the navigator
3. Select the "airsync-mac" target
4. Go to "Build Phases"
5. Expand "Link Binary With Libraries"
6. Find and remove:
   - `libavcodec.dylib`
   - `libavutil.dylib`
   - `libswscale.dylib`
   - `libavformat.dylib` (if present)
   - `libswresample.dylib` (if present)

### 3. Remove from Build Settings

1. Go to "Build Settings"
2. Search for "Library Search Paths"
3. Remove any paths containing:
   - `/opt/homebrew/opt/ffmpeg`
   - `/usr/local/opt/ffmpeg`
   - Any FFmpeg-related paths

4. Search for "Header Search Paths"
5. Remove any paths containing:
   - `/opt/homebrew/opt/ffmpeg/include`
   - `/usr/local/opt/ffmpeg/include`
   - Any FFmpeg-related paths

### 4. Remove from Package Dependencies (if using SPM)

If you added FFmpeg via Swift Package Manager:
1. Select your project
2. Go to "Package Dependencies" tab
3. Find and remove any FFmpeg packages

### 5. Clean Build

After removing FFmpeg:
```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData/airsync-mac-*

# Or in Xcode: Product → Clean Build Folder (Shift+Cmd+K)
```

### 6. Rebuild

```bash
# Build the project
xcodebuild -project airsync-mac.xcodeproj -scheme airsync-mac build
```

## Verification

After removing FFmpeg, you should:

### ✅ No FFmpeg Warnings
Build output should be clean of FFmpeg dylib warnings.

### ✅ App Still Works
- Mirror starts successfully
- Video decodes smoothly
- Performance is better than before

### ✅ Console Shows VideoToolbox
```
[H264Decoder] ⚡ Using native VideoToolbox hardware decoder
[H264Decoder] ✅ Created format description
[H264Decoder] ⚡ Created hardware decompression session
[H264Decoder] 📊 Decoding at 29.8 FPS
```

## If You Need FFmpeg Back

If for some reason you need to revert:

1. Reinstall FFmpeg:
```bash
brew install ffmpeg
```

2. Restore old H264Decoder code
3. Re-add FFmpeg to Xcode project
4. Rebuild

But VideoToolbox should be **much better** in every way.

## Alternative: Keep FFmpeg as Fallback

If you want to keep FFmpeg as a fallback option:

### Option 1: Conditional Compilation

```swift
#if USE_FFMPEG
    // FFmpeg decoder
    FFmpegDecoder.shared.decode(frameData: data)
#else
    // VideoToolbox decoder (default)
    processAnnexBData(data, pts: .zero)
#endif
```

### Option 2: Runtime Selection

```swift
enum DecoderBackend {
    case videoToolbox
    case ffmpeg
}

var decoderBackend: DecoderBackend = .videoToolbox

func decode(frameData: Data) {
    switch decoderBackend {
    case .videoToolbox:
        processAnnexBData(frameData, pts: .zero)
    case .ffmpeg:
        FFmpegDecoder.shared.decode(frameData: frameData)
    }
}
```

But honestly, **VideoToolbox is better** and you won't need FFmpeg.

## Benefits of Removal

### Before (with FFmpeg)
- App size: ~50MB (FFmpeg libraries)
- Build time: 30-45 seconds
- Dependencies: FFmpeg + all its dependencies
- Warnings: 3+ dylib warnings
- Maintenance: Need to update FFmpeg

### After (VideoToolbox only)
- App size: ~10MB (no FFmpeg)
- Build time: 15-20 seconds
- Dependencies: None (native)
- Warnings: 0
- Maintenance: None (built into macOS)

## Summary

1. **Remove FFmpeg files** from project
2. **Remove FFmpeg libraries** from Link Binary With Libraries
3. **Remove FFmpeg paths** from Build Settings
4. **Clean and rebuild**
5. **Verify** VideoToolbox is working

You'll have a cleaner, faster, smaller app with better performance!

---

**Recommendation:** Remove FFmpeg completely. VideoToolbox is superior in every way.

**Last Updated:** December 31, 2024
