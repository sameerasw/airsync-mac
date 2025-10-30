# Health Data Not Rendering - Troubleshooting Guide

## Issue Description

Health data is being sent from Android but not displaying in the Mac app's Health view.

## Diagnostic Logging Added

I've added comprehensive logging to track the data flow:

### 1. WebSocket Reception
```
[websocket] 📊 Received healthSummary message
[websocket] 📊 Health data dict: {...}
[websocket] 📊 Parsing health summary with date: ...
[websocket] 📊 Created HealthSummary: steps=..., calories=..., distance=...
[websocket] 📊 Health summary sent to LiveNotificationManager
```

### 2. LiveNotificationManager Processing
```
[live-notif] 📊 Received health summary: steps=..., calories=..., distance=...
[live-notif] 📊 Updating healthSummary on main thread
[live-notif] 📊 Health summary updated, objectWillChange triggered
```

### 3. Health View Rendering
```
[health-view] 📱 View appeared, requesting health summary
[health-view] 📊 Rendering health data: steps=...
[health-view] ⚠️ No health summary data available (if no data)
```

## Debugging Steps

### Step 1: Check if Data is Being Received

Run the Mac app and check the console for these logs:

```bash
# In Xcode console, filter for:
[websocket] 📊
[live-notif] 📊
[health-view]
```

**Expected Output:**
```
[websocket] 📊 Received healthSummary message
[websocket] 📊 Health data dict: ["date": 1761761473900, "steps": 22690, ...]
[websocket] 📊 Parsing health summary with date: 1761761473900
[websocket] 📊 Created HealthSummary: steps=22690, calories=1793, distance=5.545112426519394
[websocket] 📊 Health summary sent to LiveNotificationManager
[live-notif] 📊 Received health summary: steps=22690, calories=1793, distance=5.545112426519394
[live-notif] 📊 Updating healthSummary on main thread
[live-notif] 📊 Health summary updated, objectWillChange triggered
```

### Step 2: Check if View is Observing Correctly

If you see the logs above but the view still shows "No Health Data", check:

1. **Is the Health tab visible?**
   - The view only requests data when it appears
   - Switch to the Health tab to trigger `onAppear`

2. **Is LiveNotificationManager.shared being used?**
   - The view uses `@ObservedObject private var manager = LiveNotificationManager.shared`
   - Verify it's the same instance

3. **Is the data being set on the main thread?**
   - Already handled with `DispatchQueue.main.async`

### Step 3: Verify Data Structure

Check if the Android data matches the expected format:

**Android sends:**
```json
{
  "type": "healthSummary",
  "data": {
    "date": 1761761473900,
    "steps": 22690,
    "distance": 5.545112426519394,
    "calories": 1793,
    "activeMinutes": 0,
    "heartRateAvg": null,
    "heartRateMin": null,
    "heartRateMax": null,
    "sleepDuration": 20
  }
}
```

**Mac expects:**
```swift
struct HealthSummary: Codable {
    let date: Date
    let steps: Int?
    let distance: Double?
    let calories: Int?
    let activeMinutes: Int?
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let heartRateMax: Int?
    let sleepDuration: Int?
}
```

### Step 4: Check Message Type Enum

Verify that `MessageType` includes `healthSummary`:

```swift
enum MessageType: String, Codable {
    // ... other cases
    case healthSummary
    case healthData
    case requestHealthSummary
    case requestHealthData
}
```

## Common Issues & Solutions

### Issue 1: Data Received but View Shows "No Health Data"

**Symptoms:**
- Logs show data being received and processed
- View still shows empty state
- No rendering logs

**Possible Causes:**
1. View is not observing LiveNotificationManager correctly
2. ObservableObject not publishing changes
3. View not on screen when data arrives

**Solutions:**

1. **Force View Update:**
```swift
struct HealthView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    @State private var refreshID = UUID()
    
    var body: some View {
        ScrollView {
            // ... content
        }
        .id(refreshID)
        .onReceive(manager.$healthSummary) { _ in
            refreshID = UUID()
        }
    }
}
```

2. **Verify @Published:**
```swift
class LiveNotificationManager: ObservableObject {
    @Published var healthSummary: HealthSummary? // ✅ Must have @Published
}
```

3. **Check if View is Active:**
- Switch to Health tab
- Wait 1-2 seconds
- Check if data appears

### Issue 2: Date Parsing Fails

**Symptoms:**
```
[websocket] ❌ Failed to parse date from health summary
```

**Cause:**
- Android sends date as Int64 milliseconds
- Mac expects Int64 but gets different type

**Solution:**
```swift
// Try different parsing approaches
if let dateMs = dict["date"] as? Int64 {
    // Works for Int64
} else if let dateMs = dict["date"] as? Double {
    // Works for Double
    let summary = HealthSummary(
        date: Date(timeIntervalSince1970: dateMs / 1000.0),
        // ...
    )
} else if let dateMs = dict["date"] as? Int {
    // Works for Int
    let summary = HealthSummary(
        date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
        // ...
    )
}
```

### Issue 3: Data Dict Parsing Fails

**Symptoms:**
```
[websocket] ❌ Failed to parse health summary data dict
```

**Cause:**
- `message.data.value` is not a dictionary
- Data is wrapped differently

**Solution:**
```swift
// Add more detailed logging
print("[websocket] message.data type: \(type(of: message.data))")
print("[websocket] message.data.value type: \(type(of: message.data.value))")

// Try alternative parsing
if let dataDict = message.data.value as? [String: Any] {
    // Current approach
} else if let dataString = message.data.value as? String {
    // Parse JSON string
    if let data = dataString.data(using: .utf8),
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        // Use dict
    }
}
```

### Issue 4: MessageType Not Recognized

**Symptoms:**
```
[websocket] Warning: unhandled message type: healthSummary
```

**Cause:**
- `MessageType` enum doesn't include `healthSummary`
- Case name mismatch

**Solution:**

Check `Message.swift`:
```swift
enum MessageType: String, Codable {
    case device
    case notification
    case status
    // ... other cases
    case healthSummary  // ✅ Must be present
    case healthData
    case requestHealthSummary
    case requestHealthData
}
```

## Testing Checklist

- [ ] Android sends health data (check Android logs)
- [ ] Mac receives WebSocket message (check Mac logs)
- [ ] Message type is recognized as `healthSummary`
- [ ] Data dict is parsed successfully
- [ ] Date is parsed from milliseconds
- [ ] HealthSummary object is created
- [ ] LiveNotificationManager receives data
- [ ] Data is set on main thread
- [ ] @Published property triggers update
- [ ] Health view is visible/active
- [ ] View receives update notification
- [ ] Cards are rendered with data

## Manual Test

1. **Open Mac App**
   - Launch AirSync on Mac
   - Connect to Android device
   - Navigate to Health tab

2. **Trigger Data Request**
   - Health view automatically requests data on appear
   - Or manually: `WebSocketServer.shared.requestHealthSummary()`

3. **Check Android Response**
   - Android should send healthSummary message
   - Check Android logs for "Sent health summary"

4. **Check Mac Reception**
   - Mac should log "Received healthSummary message"
   - Should log "Created HealthSummary: steps=..."
   - Should log "Health summary updated"

5. **Verify Display**
   - Health cards should appear
   - Steps, calories, distance should show
   - Progress bars should render

## Quick Fix

If data is being received but not displaying, try this immediate fix:

```swift
// In ModernHealthView.swift
struct HealthView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    
    var body: some View {
        ScrollView {
            // Add this debug view
            if let summary = manager.healthSummary {
                Text("DEBUG: Steps = \(summary.steps ?? 0)")
                    .foregroundColor(.red)
                    .font(.title)
            }
            
            // Rest of the view...
        }
    }
}
```

If the debug text appears, the data is there but the cards aren't rendering. If it doesn't appear, the data isn't reaching the view.

## Expected Behavior

When working correctly, you should see:

1. **Android logs:**
```
Sending message: {"type":"healthSummary","data":{...}}
Sent health summary
```

2. **Mac logs:**
```
[websocket] 📊 Received healthSummary message
[websocket] 📊 Created HealthSummary: steps=22690, calories=1793
[live-notif] 📊 Received health summary: steps=22690
[live-notif] 📊 Health summary updated
[health-view] 📊 Rendering health data: steps=22690
```

3. **Mac UI:**
- Health tab shows 6 cards (or fewer if some data is null)
- Steps card shows "22,690" with progress bar
- Calories card shows "1,793 kcal" with progress bar
- Distance card shows "5.5 km"
- Sleep card shows "0h 20m" with progress bar
- Active minutes card shows "0 minutes"

## Next Steps

1. Run the app with the new logging
2. Check console output
3. Identify which step is failing
4. Apply the appropriate solution from above
5. Report back with the specific logs you're seeing

The logging will tell us exactly where the data flow is breaking.
