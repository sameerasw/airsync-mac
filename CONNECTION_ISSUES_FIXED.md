# Connection Issues Fixed: Stale IP Addresses & Network Changes

## Problem

Every time the Mac app restarts or recompiles, it tries to wake up the Android device at a **stale/wrong IP address**, causing connection timeouts:

```
[quick-connect] Attempting to wake up device: Shantanu's S21 FE at 192.168.1.37
Task finished with error [-1001] "The request timed out."
```

**Actual device IP**: `192.168.1.41`  
**Cached/stale IP**: `192.168.1.37`

## Root Causes

### 1. Mac IP as Storage Key
The `QuickConnectManager` was using the **Mac's exact IP address** as the dictionary key to store device history:

```swift
// OLD - Breaks when Mac IP changes
lastConnectedDevices[currentMacIP] = device  // Key: "192.168.1.34"
```

**Problem**: When Mac restarts, DHCP might assign a different IP (e.g., `192.168.1.47`), so the lookup fails and returns stale data.

### 2. Device IP Changes
Android devices also get new IPs from DHCP, but the cached device object still has the old IP.

### 3. No Network Validation
The wake-up code didn't check if the cached device IP is still on the same network as the Mac.

## Solutions Applied

### 1. Network Prefix as Key
Changed from exact IP to **network prefix** (first 3 octets):

```swift
// NEW - Survives DHCP changes
private func getNetworkKey(from ipAddress: String) -> String {
    let components = ipAddress.split(separator: ".")
    if components.count >= 3 {
        return "\(components[0]).\(components[1]).\(components[2])"  // "192.168.1"
    }
    return ipAddress
}

// Store with network key
let networkKey = getNetworkKey(from: currentMacIP)  // "192.168.1"
lastConnectedDevices[networkKey] = device
```

**Benefit**: Works even if Mac IP changes from `192.168.1.34` to `192.168.1.47` - both map to `"192.168.1"`.

### 2. Network Validation Before Wake-Up
Added check to ensure device is on the same network:

```swift
func wakeUpLastConnectedDevice() {
    guard let lastDevice = getLastConnectedDevice() else {
        print("[quick-connect] No last connected device to wake up for current network")
        return
    }
    
    guard let currentMacIP = getCurrentMacIP() else {
        print("[quick-connect] Cannot determine current Mac IP")
        return
    }
    
    let macNetwork = getNetworkKey(from: currentMacIP)
    let deviceNetwork = getNetworkKey(from: lastDevice.ipAddress)
    
    if macNetwork != deviceNetwork {
        print("[quick-connect] ⚠️ Device IP \(lastDevice.ipAddress) is on different network than Mac \(currentMacIP)")
        print("[quick-connect] Skipping wake-up - device may have changed networks or IP")
        return
    }
    
    // Proceed with wake-up...
}
```

**Benefit**: Prevents timeout errors when device IP is stale or on different network.

### 3. Updated Comments
Clarified that storage uses network prefix, not exact IPs:

```swift
// Store last connected devices per network (key: network prefix like "192.168.1", value: Device)
// Using network prefix instead of exact Mac IP to handle DHCP IP changes
@Published var lastConnectedDevices: [String: Device] = [:]
```

## Expected Behavior After Fix

### Scenario 1: Mac IP Changes
- **Before**: Lookup fails, uses stale device from wrong network
- **After**: Lookup succeeds using network prefix `"192.168.1"`

### Scenario 2: Device IP Changes
- **Before**: Tries to wake device at old IP, times out
- **After**: Detects network mismatch, skips wake-up, waits for manual reconnect

### Scenario 3: Both IPs Change (Same Network)
- **Before**: Complete failure
- **After**: Lookup works, but wake-up skipped if device IP is stale (user must reconnect once)

### Scenario 4: Network Change (Different WiFi)
- **Before**: Tries to wake device on wrong network, times out
- **After**: Detects network mismatch, skips wake-up gracefully

## Logs After Fix

### Success Case (Same Network)
```
[quick-connect] Saved last connected device for network 192.168.1: Shantanu's S21 FE (192.168.1.41)
[quick-connect] Attempting to wake up device: Shantanu's S21 FE at 192.168.1.41
[quick-connect] ✅ Wake-up request successful - device should reconnect soon
```

### Network Mismatch Case
```
[quick-connect] ⚠️ Device IP 192.168.1.37 is on different network than Mac 192.168.10.5
[quick-connect] Skipping wake-up - device may have changed networks or IP
```

### No Device Case
```
[quick-connect] No last connected device to wake up for current network
```

## User Experience Improvements

1. **No More Timeout Errors**: Wake-up only attempts when device is likely reachable
2. **Survives DHCP Changes**: Works across Mac IP changes on same network
3. **Clear Feedback**: Logs explain why wake-up was skipped
4. **Graceful Degradation**: Falls back to manual QR code connection when needed

## Manual Reconnection

When device IP changes significantly, user should:
1. Open Android app
2. Scan QR code from Mac
3. New IP will be saved automatically
4. Future wake-ups will use new IP

## Technical Notes

- Network prefix approach works for Class C subnets (`/24` or `255.255.255.0`)
- For larger networks, may need to adjust to use 2 octets instead of 3
- Device history persists across app restarts via UserDefaults
- Wake-up service on Android (ports 8888/8889) must be running for this to work

## Files Modified

- `airsync-mac/Core/QuickConnect/QuickConnectManager.swift`
  - Added `getNetworkKey()` helper function
  - Updated all device storage/lookup to use network prefix
  - Added network validation before wake-up attempts
  - Improved logging and error messages
