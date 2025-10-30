# Connection Test Guide

## Current Status
✅ Mac server is running at: `ws://192.168.1.47:6996/socket`
❌ Android can't connect: "Failed to connect to /192.168.1.47:6996"

## Issue Analysis

The Android error shows `/192.168.1.47:6996` instead of `ws://192.168.1.47:6996/socket`

This suggests the Android app might be:
1. Missing the `ws://` protocol prefix
2. Missing the `/socket` endpoint path
3. Using wrong URL construction

## Quick Tests

### Test 1: Verify Mac Server is Accessible
From your Mac terminal, test if the server is listening:

```bash
# Check if port is open
nc -zv 192.168.1.47 6996

# Or use netstat
netstat -an | grep 6996

# Or use lsof
lsof -i :6996
```

Expected output: Connection succeeded or port is LISTENING

### Test 2: Test WebSocket from Another Tool
Use a WebSocket testing tool to verify the server works:

**Option A: Using websocat (if installed)**
```bash
brew install websocat
websocat ws://192.168.1.47:6996/socket
```

**Option B: Using wscat (if installed)**
```bash
npm install -g wscat
wscat -c ws://192.168.1.47:6996/socket
```

**Option C: Online WebSocket Tester**
1. Go to: https://www.websocket.org/echo.html
2. Enter: `ws://192.168.1.47:6996/socket`
3. Click "Connect"

If connection succeeds, the Mac server is working correctly.

### Test 3: Check Android WebSocket URL Construction

The Android app needs to construct the URL as:
```kotlin
val url = "ws://${macIP}:${macPort}/socket"
// Should be: ws://192.168.1.47:6996/socket
```

Common mistakes:
- ❌ `/192.168.1.47:6996` (missing protocol)
- ❌ `ws://192.168.1.47:6996` (missing /socket endpoint)
- ❌ `http://192.168.1.47:6996/socket` (wrong protocol)
- ✅ `ws://192.168.1.47:6996/socket` (correct)

## Android Code Fixes

### Check 1: WebSocket URL Construction
Look for where the WebSocket URL is built in Android code:

```kotlin
// WRONG - Missing protocol
val url = "/${macIP}:${macPort}"

// WRONG - Missing endpoint
val url = "ws://${macIP}:${macPort}"

// CORRECT
val url = "ws://${macIP}:${macPort}/socket"
```

### Check 2: OkHttp WebSocket Client
Ensure the Android app is using OkHttp correctly:

```kotlin
val client = OkHttpClient.Builder()
    .connectTimeout(10, TimeUnit.SECONDS)
    .readTimeout(10, TimeUnit.SECONDS)
    .writeTimeout(10, TimeUnit.SECONDS)
    .pingInterval(30, TimeUnit.SECONDS)
    .build()

val request = Request.Builder()
    .url("ws://192.168.1.47:6996/socket")
    .build()

val listener = object : WebSocketListener() {
    override fun onOpen(webSocket: WebSocket, response: Response) {
        Log.d("WebSocket", "✅ Connected!")
        // Send device info here
    }
    
    override fun onMessage(webSocket: WebSocket, text: String) {
        Log.d("WebSocket", "📨 Received: $text")
    }
    
    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        Log.e("WebSocket", "❌ Failed: ${t.message}")
        t.printStackTrace()
    }
    
    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        Log.d("WebSocket", "Closing: $code - $reason")
    }
    
    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        Log.d("WebSocket", "Closed: $code - $reason")
    }
}

client.newWebSocket(request, listener)
```

### Check 3: Network Permissions
Ensure AndroidManifest.xml has:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- For Android 9+ cleartext traffic -->
<application
    android:usesCleartextTraffic="true"
    ...>
```

### Check 4: Network Security Config
For Android 9+, you might need a network security config:

**res/xml/network_security_config.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
</network-security-config>
```

**AndroidManifest.xml:**
```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

## Debugging Steps

### Step 1: Add Detailed Logging
In Android WebSocket code, add:

```kotlin
Log.d("WebSocket", "Attempting to connect to: $url")
Log.d("WebSocket", "Mac IP: $macIP")
Log.d("WebSocket", "Mac Port: $macPort")
Log.d("WebSocket", "Full URL: ws://$macIP:$macPort/socket")
```

### Step 2: Test with Hardcoded URL
Temporarily hardcode the URL to eliminate variable issues:

```kotlin
val url = "ws://192.168.1.47:6996/socket"
Log.d("WebSocket", "Connecting to hardcoded URL: $url")
```

### Step 3: Check Network Connectivity
Before connecting, verify network:

```kotlin
fun isNetworkAvailable(context: Context): Boolean {
    val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val network = connectivityManager.activeNetwork ?: return false
    val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
    return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
}

if (!isNetworkAvailable(context)) {
    Log.e("WebSocket", "No WiFi connection!")
    return
}
```

### Step 4: Test Raw Socket Connection
Before WebSocket, test if you can reach the server at all:

```kotlin
fun testConnection(host: String, port: Int) {
    Thread {
        try {
            val socket = Socket()
            socket.connect(InetSocketAddress(host, port), 5000)
            Log.d("Connection", "✅ TCP connection successful!")
            socket.close()
        } catch (e: Exception) {
            Log.e("Connection", "❌ TCP connection failed: ${e.message}")
        }
    }.start()
}

testConnection("192.168.1.47", 6996)
```

## Common Issues & Solutions

### Issue: "Failed to connect to /192.168.1.47:6996"
**Cause:** URL is missing `ws://` protocol
**Fix:** Ensure URL starts with `ws://`

### Issue: "Connection refused"
**Cause:** Server not running or firewall blocking
**Fix:** 
1. Verify Mac server is running (check logs)
2. Test with `nc -zv 192.168.1.47 6996`
3. Temporarily disable Mac firewall to test

### Issue: "Connection timeout"
**Cause:** Network routing issue or wrong IP
**Fix:**
1. Verify both devices on same WiFi
2. Ping Mac from Android: `ping 192.168.1.47`
3. Check Mac IP hasn't changed

### Issue: "SSL/TLS error"
**Cause:** Trying to use `wss://` instead of `ws://`
**Fix:** Use `ws://` (not `wss://`) for unencrypted WebSocket

## Next Steps

1. **Run Test 1** to verify Mac server is accessible
2. **Check Android logs** for the exact URL being used
3. **Add detailed logging** to Android WebSocket connection code
4. **Test with hardcoded URL** to eliminate variable issues
5. **Share the Android WebSocket connection code** so I can review it

## Expected Flow

When working correctly, you should see:

**Mac logs:**
```
[websocket] WebSocket server started at ws://192.168.1.47:6996/socket
[websocket] Device connected
[websocket] Active sessions: 1
[websocket] [raw] incoming text length=XXX
[websocket] [received] {"type":"device",...}
```

**Android logs:**
```
WebSocket: Connecting to ws://192.168.1.47:6996/socket
WebSocket: ✅ Connected!
WebSocket: Sending device info...
```
