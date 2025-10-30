# Current Issues and Fixes

## Issues Found in Logs

### 1. Empty Data Dictionaries ❌
```
[websocket] 📞 Call logs data dict keys: []
[websocket] 📱 SMS data dict keys: []
[websocket] 📊 Health data dict: [:]
```

**Problem:** `CodableValue` is decoding to empty dictionaries

**Fix Applied:** Added detailed logging to `CodableValue` decoder to see what's happening

**Next Steps:** Run app and check logs for:
```
[CodableValue] ✅ Decoded dictionary with X keys: ...
```

### 2. VideoToolbox Format Description Error ❌
```
[H264Decoder] ❌ Failed to create format description: -12712
```

**Problem:** `-12712` = `kVTParameterErr` - Invalid SPS/PPS parameter sets

**Possible Causes:**
1. Android sending malformed SPS/PPS
2. SPS/PPS not being extracted correctly
3. Start codes not being removed properly

**Fix Applied:** Added detailed logging to show:
- SPS/PPS sizes
- First bytes of SPS/PPS (hex dump)
- Specific error names

**Next Steps:** Check logs for:
```
[H264Decoder] 🔧 Creating format description with SPS(X bytes) PPS(Y bytes)
[H264Decoder] 📊 SPS first bytes: 67 42 00 1F ...
[H264Decoder] 📊 PPS first bytes: 68 CE 3C 80 ...
```

### 3. Date Mismatch ⚠️
```
[health-view] 📅 Requesting health data for: 30 Oct 2025
[websocket] 📅 Requesting... timestamp: 1761764211835
Android sends: "date":1761762600000 (different date)
```

**Problem:** Android ignores requested date, always sends today

**Status:** Known issue - Android needs implementation

---

## Expected Behavior After Fixes

### Data Parsing
```
[CodableValue] ✅ Decoded dictionary with 8 keys: date, steps, distance, calories, ...
[websocket] 📊 Health data dict: ["date": 1761762600000, "steps": 9724, ...]
[websocket] 📊 Parsing health summary with date: 1761762600000
[live-notif] 📊 Received health summary: steps=9724, calories=1748
[health-view] 📊 Rendering health data: steps=9724
```

### VideoToolbox Decoder
```
[H264Decoder] 🔧 Creating format description with SPS(25 bytes) PPS(4 bytes)
[H264Decoder] ✅ Created format description
[H264Decoder] ⚡ Created hardware decompression session
[H264Decoder] 📊 Decoding at 29.8 FPS
```

---

## Debugging Steps

### 1. Check CodableValue Decoding

Run the app and look for:
```
[CodableValue] ✅ Decoded dictionary with X keys: ...
```

If you see:
```
[CodableValue] ⚠️ Failed to decode, using empty dictionary
```

Then the JSON structure is not what we expect.

### 2. Check VideoToolbox SPS/PPS

Look for:
```
[H264Decoder] 🔧 Creating format description with SPS(X bytes) PPS(Y bytes)
[H264Decoder] 📊 SPS first bytes: ...
[H264Decoder] 📊 PPS first bytes: ...
```

**Valid SPS should start with:** `67` (0x67)
**Valid PPS should start with:** `68` (0x68)

If they start with `00 00 00 01`, the start codes weren't removed.

### 3. Check Android Encoder

**Android should send:**
```kotlin
// SPS NAL (type 7)
val sps = byteArrayOf(0x67, 0x42, 0x00, 0x1F, ...)

// PPS NAL (type 8)  
val pps = byteArrayOf(0x68, 0xCE, 0x3C, 0x80, ...)

// Send as config frame
val configFrame = sps + pps
sendMirrorFrame(configFrame, isConfig = true)
```

---

## Common Issues

### Issue: Empty Dictionaries

**Symptom:**
```
[websocket] 📊 Health data dict: [:]
```

**Cause:** JSON decoding failing

**Check:**
1. Is the JSON valid?
2. Is it being truncated?
3. Is the structure correct?

**Fix:** Look at the full JSON in logs (not truncated)

### Issue: VideoToolbox -12712 Error

**Symptom:**
```
[H264Decoder] ❌ Failed to create format description: -12712
```

**Cause:** Invalid SPS/PPS

**Common Problems:**
1. **Start codes not removed:** SPS/PPS should NOT start with `00 00 00 01`
2. **Wrong NAL type:** SPS must be type 7, PPS must be type 8
3. **Corrupted data:** Network packet loss or encoding error

**Fix:**
```kotlin
// Android: Remove start codes before sending
fun extractParameterSets(configBuffer: ByteBuffer): Pair<ByteArray, ByteArray> {
    // Find SPS (starts with 0x67)
    // Find PPS (starts with 0x68)
    // Return WITHOUT start codes
}
```

### Issue: Date Mismatch

**Symptom:**
```
Mac requests: Oct 28
Android sends: Oct 29 (today)
```

**Cause:** Android not implementing date-specific fetching

**Fix:** See `ANDROID_DATE_SPECIFIC_HEALTH_FIX.md`

---

## Testing Checklist

### After Rebuild

- [ ] Check `[CodableValue]` logs show successful decoding
- [ ] Check health data dict has keys
- [ ] Check SMS/call logs dict has keys
- [ ] Check VideoToolbox creates format description
- [ ] Check VideoToolbox creates decompression session
- [ ] Check FPS reaches 28-30
- [ ] Check latency drops below 200ms
- [ ] Check dropped frames < 5%

### If Still Failing

1. **Copy full logs** (not truncated)
2. **Check Android logs** for encoder output
3. **Verify JSON structure** matches expected format
4. **Check SPS/PPS hex dump** for start codes
5. **Test with sample data** from `ANDROID_MESSAGE_FORMATS_GUIDE.md`

---

## Quick Fixes

### Force FFmpeg Fallback (if VideoToolbox fails)

If VideoToolbox continues to fail, you can temporarily fall back to FFmpeg:

```swift
// In H264Decoder.swift
func decode(frameData: Data, isConfig: Bool) {
    // Temporary fallback to FFmpeg
    FFmpegDecoder.shared.decode(frameData: frameData)
    return
    
    // VideoToolbox code...
}
```

But this should only be temporary - VideoToolbox should work and is much better.

### Test with Known Good Data

Create a test with valid H.264 data:

```swift
// Test SPS/PPS
let testSPS = Data([0x67, 0x42, 0x00, 0x1F, 0xDA, 0x01, 0x40, 0x16, 0xEC, 0x04, 0x40, 0x00, 0x00, 0x03, 0x00, 0x40, 0x00, 0x00, 0x0F, 0x03, 0xC5, 0x8B, 0x65, 0x80])
let testPPS = Data([0x68, 0xCE, 0x3C, 0x80])

createFormatDescription(sps: testSPS, pps: testPPS)
// Should succeed
```

---

## Summary

**Added Logging:**
- ✅ CodableValue decoding details
- ✅ VideoToolbox error names
- ✅ SPS/PPS hex dumps
- ✅ Parameter set sizes

**Next Steps:**
1. Rebuild and run app
2. Check new logs
3. Identify specific failure point
4. Apply appropriate fix

The detailed logging will tell us exactly what's failing and why.

---

**Last Updated:** December 31, 2024
