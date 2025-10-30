# Critical Issues Fixed: H264 Decoder & File Transfer Checksum

## Issue 1: H264 Decoder Error (-12712) ❌

### Problem
```
[H264Decoder] ❌ Failed to create format description: -12712 (kVTParameterErr)
[H264Decoder] 📊 SPS first bytes: 67 42 C0 1F DA 01 0C 04
[H264Decoder] 🔄 Falling back to FFmpeg software decoder
```

### Root Cause
The Android encoder is using **H.264 Baseline Profile (0x42)** which VideoToolbox on Apple Silicon (M4 Mac) rejects with `kVTParameterErr`.

**SPS Analysis:**
- Byte 0: `0x67` = NAL type 7 (SPS)
- Byte 1: `0x42` = **Baseline Profile** ⚠️
- Byte 2: `0xC0` = Constraints
- Byte 3: `0x1F` = Level 3.1

### Why This Fails
VideoToolbox on Apple Silicon (M1/M2/M3/M4) has strict requirements:
- Prefers **Main Profile (0x4D)** or **High Profile (0x64)**
- Baseline profile lacks features like CABAC, B-frames
- Hardware decoder optimized for modern profiles

### Solution (Android Side)
Change the MediaCodec encoder configuration:

```kotlin
// WRONG - Causes -12712 error
format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)

// CORRECT - Works with VideoToolbox
format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileMain)
// OR
format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
```

### Mac Side Fix Applied
Added profile detection and better error messages:
- Detects Baseline profile and warns
- Provides clear guidance for Android fix
- Automatically falls back to FFmpeg when VideoToolbox fails

---

## Issue 2: File Transfer Checksum Mismatch ❌

### Problem
File transfers complete but checksums don't match, causing verification failures.

### Root Cause
**Algorithm Mismatch:**
- **Android**: Likely using MD5 (32 hex characters)
- **Mac**: Using SHA256 (64 hex characters)

### Detection Logic Added
```swift
// Check if Android sent MD5 (32 chars) instead of SHA256 (64 chars)
if expected.count == 32 && computed.count == 64 {
    print("⚠️ MISMATCH: Android sent MD5 but Mac computed SHA256")
}
```

### Solution (Android Side)
Replace MD5 with SHA256:

```kotlin
// WRONG - MD5 (deprecated, insecure)
val md = MessageDigest.getInstance("MD5")
val checksum = md.digest(fileBytes).joinToString("") { "%02x".format(it) }

// CORRECT - SHA256 (secure, matches Mac)
val md = MessageDigest.getInstance("SHA-256")
val checksum = md.digest(fileBytes).joinToString("") { "%02x".format(it) }
```

### Mac Side Fix Applied
Enhanced checksum verification:
- Detects algorithm mismatch (MD5 vs SHA256)
- Logs expected vs computed checksums with lengths
- Provides clear error messages for debugging
- Shows specific notification when algorithm mismatch detected

---

## Testing After Android Fixes

### Test H264 Decoder
1. Apply Android encoder profile fix (Main or High)
2. Start mirroring from Android
3. Check Mac logs for:
   ```
   [H264Decoder] 📊 Detected profile: Main
   [H264Decoder] ✅ Created format description
   [H264Decoder] ⚡ Created hardware decompression session
   ```
4. Verify no fallback to FFmpeg occurs

### Test File Transfer
1. Apply Android SHA256 checksum fix
2. Send a file from Android to Mac
3. Check Mac logs for:
   ```
   [websocket] (file-transfer) Expected length: 64, Computed length: 64
   [websocket] (file-transfer) ✅ Checksum verified successfully
   ```
4. Verify no mismatch notifications

---

## Android Code Locations to Fix

### 1. H264 Encoder Configuration
Look for:
- `MediaCodec.createEncoderByType("video/avc")`
- `MediaFormat.createVideoFormat()`
- `KEY_PROFILE` setting

### 2. File Transfer Checksum
Look for:
- `MessageDigest.getInstance("MD5")`
- File transfer initialization
- Checksum calculation before sending

---

## Performance Impact

### Before Fix
- **H264**: Falls back to FFmpeg software decoder (slower, higher CPU)
- **File Transfer**: All transfers show checksum mismatch warnings

### After Fix
- **H264**: Uses VideoToolbox hardware decoder (faster, lower CPU, better battery)
- **File Transfer**: Proper verification, no false warnings

---

## Summary

Both issues are **Android-side problems** that need fixes in the Android app:

1. **H264 Encoder**: Change from Baseline to Main/High profile
2. **File Checksum**: Change from MD5 to SHA256

Mac side now:
- Detects and reports both issues clearly
- Provides actionable guidance for Android developers
- Gracefully handles the issues with fallbacks
