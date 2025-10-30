# Health Data Date Picker - Implementation Guide

## Overview

Implemented a date-based health data viewer that allows users to:
- View health data for any past date
- Navigate between dates with arrow buttons
- Jump to today with a "Today" button
- Automatically request data when date changes
- Show loading state while fetching data

## Mac Side (Completed) ✅

### 1. Enhanced Health View

**Features:**
- Date picker to select any date (up to today)
- Previous/Next day navigation buttons
- "Today" button to jump to current date
- Refresh button to reload data
- Loading indicator while fetching
- Automatic data request on date change
- Date validation (only shows data for selected date)

**UI Components:**
```swift
// Date Picker Header
- Previous Day Button (←)
- Date Picker (compact style)
- Next Day Button (→, disabled for today)
- Today Button (only shown when not today)
- Refresh Button (with rotation animation)
```

### 2. Updated WebSocket Methods

**requestHealthSummary(for:)**
```swift
func requestHealthSummary(for date: Date? = nil) {
    let targetDate = date ?? Date()
    let dateMs = Int64(targetDate.timeIntervalSince1970 * 1000)
    
    let message = """
    {
        "type": "requestHealthSummary",
        "data": {
            "date": \(dateMs)
        }
    }
    """
    sendToFirstAvailable(message: message)
}
```

**Message Format:**
```json
{
  "type": "requestHealthSummary",
  "data": {
    "date": 1735689600000
  }
}
```

## Android Side (To Implement)

### 1. Update WebSocketMessageHandler

Handle date parameter in health data requests:

```kotlin
when (message.type) {
    "requestHealthSummary" -> {
        val data = message.data
        val dateMs = data?.optLong("date") ?: System.currentTimeMillis()
        val date = Date(dateMs)
        
        Log.d(TAG, "Requesting health summary for date: $date")
        
        // Fetch health data for specific date
        healthDataManager.fetchHealthSummary(date) { summary ->
            sendHealthSummary(summary)
        }
    }
    
    "requestHealthData" -> {
        val data = message.data
        val hours = data?.optInt("hours", 24) ?: 24
        val dateMs = data?.optLong("date") ?: System.currentTimeMillis()
        val date = Date(dateMs)
        
        Log.d(TAG, "Requesting health data for $hours hours from date: $date")
        
        // Fetch detailed health data
        healthDataManager.fetchHealthData(date, hours) { records ->
            sendHealthData(records)
        }
    }
}
```

### 2. Update Health Data Manager

Fetch data for specific date range:

```kotlin
class HealthDataManager(private val context: Context) {
    
    fun fetchHealthSummary(date: Date, callback: (HealthSummary) -> Unit) {
        // Get start and end of the selected day
        val calendar = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startTime = calendar.timeInMillis
        
        calendar.add(Calendar.DAY_OF_MONTH, 1)
        val endTime = calendar.timeInMillis
        
        Log.d(TAG, "Fetching health data from $startTime to $endTime")
        
        lifecycleScope.launch {
            try {
                val summary = aggregateHealthData(startTime, endTime)
                callback(summary)
            } catch (e: Exception) {
                Log.e(TAG, "Error fetching health summary", e)
                callback(createEmptySummary(date))
            }
        }
    }
    
    private suspend fun aggregateHealthData(startTime: Long, endTime: Long): HealthSummary {
        val healthConnectClient = HealthConnectClient.getOrCreate(context)
        
        // Fetch steps
        val stepsRequest = ReadRecordsRequest(
            recordType = StepsRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val stepsResponse = healthConnectClient.readRecords(stepsRequest)
        val totalSteps = stepsResponse.records.sumOf { it.count }
        
        // Fetch distance
        val distanceRequest = ReadRecordsRequest(
            recordType = DistanceRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val distanceResponse = healthConnectClient.readRecords(distanceRequest)
        val totalDistance = distanceResponse.records.sumOf { 
            it.distance.inKilometers 
        }
        
        // Fetch calories
        val caloriesRequest = ReadRecordsRequest(
            recordType = TotalCaloriesBurnedRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val caloriesResponse = healthConnectClient.readRecords(caloriesRequest)
        val totalCalories = caloriesResponse.records.sumOf { 
            it.energy.inKilocalories.toInt()
        }
        
        // Fetch heart rate
        val heartRateRequest = ReadRecordsRequest(
            recordType = HeartRateRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val heartRateResponse = healthConnectClient.readRecords(heartRateRequest)
        val heartRates = heartRateResponse.records.flatMap { it.samples.map { s -> s.beatsPerMinute } }
        val avgHeartRate = if (heartRates.isNotEmpty()) heartRates.average().toInt() else null
        val minHeartRate = heartRates.minOrNull()?.toInt()
        val maxHeartRate = heartRates.maxOrNull()?.toInt()
        
        // Fetch sleep
        val sleepRequest = ReadRecordsRequest(
            recordType = SleepSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val sleepResponse = healthConnectClient.readRecords(sleepRequest)
        val totalSleepMinutes = sleepResponse.records.sumOf { 
            Duration.between(it.startTime, it.endTime).toMinutes().toInt()
        }
        
        // Fetch active minutes
        val activeRequest = ReadRecordsRequest(
            recordType = ActiveCaloriesBurnedRecord::class,
            timeRangeFilter = TimeRangeFilter.between(
                Instant.ofEpochMilli(startTime),
                Instant.ofEpochMilli(endTime)
            )
        )
        val activeResponse = healthConnectClient.readRecords(activeRequest)
        val activeMinutes = activeResponse.records.sumOf {
            Duration.between(it.startTime, it.endTime).toMinutes().toInt()
        }
        
        return HealthSummary(
            date = startTime,
            steps = totalSteps.toInt(),
            distance = totalDistance,
            calories = totalCalories,
            activeMinutes = activeMinutes,
            heartRateAvg = avgHeartRate,
            heartRateMin = minHeartRate,
            heartRateMax = maxHeartRate,
            sleepDuration = totalSleepMinutes
        )
    }
    
    private fun createEmptySummary(date: Date): HealthSummary {
        return HealthSummary(
            date = date.time,
            steps = null,
            distance = null,
            calories = null,
            activeMinutes = null,
            heartRateAvg = null,
            heartRateMin = null,
            heartRateMax = null,
            sleepDuration = null
        )
    }
}
```

### 3. Health Summary Data Class

```kotlin
data class HealthSummary(
    val date: Long,  // Timestamp in milliseconds
    val steps: Int?,
    val distance: Double?,  // in kilometers
    val calories: Int?,
    val activeMinutes: Int?,
    val heartRateAvg: Int?,
    val heartRateMin: Int?,
    val heartRateMax: Int?,
    val sleepDuration: Int?  // in minutes
)
```

### 4. Send Response to Mac

```kotlin
fun sendHealthSummary(summary: HealthSummary) {
    val message = JSONObject().apply {
        put("type", "healthSummary")
        put("data", JSONObject().apply {
            put("date", summary.date)
            put("steps", summary.steps)
            put("distance", summary.distance)
            put("calories", summary.calories)
            put("activeMinutes", summary.activeMinutes)
            put("heartRateAvg", summary.heartRateAvg)
            put("heartRateMin", summary.heartRateMin)
            put("heartRateMax", summary.heartRateMax)
            put("sleepDuration", summary.sleepDuration)
        })
    }
    
    webSocket.send(message.toString())
    Log.d(TAG, "Sent health summary for date: ${Date(summary.date)}")
}
```

## User Flow

### 1. Default Behavior (Today's Data)

```
User opens Health tab
    ↓
View appears with today's date selected
    ↓
Mac sends: {"type":"requestHealthSummary","data":{"date":1735689600000}}
    ↓
Android fetches today's health data
    ↓
Android sends: {"type":"healthSummary","data":{...}}
    ↓
Mac displays health cards
```

### 2. Selecting Previous Date

```
User clicks date picker
    ↓
User selects December 25, 2024
    ↓
Mac sends: {"type":"requestHealthSummary","data":{"date":1735084800000}}
    ↓
Android fetches Dec 25 health data
    ↓
Android sends: {"type":"healthSummary","data":{...}}
    ↓
Mac displays health cards for Dec 25
```

### 3. Navigation with Arrows

```
User clicks ← (Previous Day)
    ↓
Date changes to yesterday
    ↓
Mac automatically requests yesterday's data
    ↓
Android fetches and sends data
    ↓
Mac displays yesterday's health cards
```

## UI Features

### Date Picker Header

```
┌─────────────────────────────────────────────────┐
│  ←  [Dec 31, 2024 ▼]  →    [Today]  ↻         │
└─────────────────────────────────────────────────┘
```

**Components:**
- **← Button**: Go to previous day
- **Date Picker**: Select any date (up to today)
- **→ Button**: Go to next day (disabled if today)
- **Today Button**: Jump to today (hidden if already today)
- **↻ Button**: Refresh current date's data

### Loading State

When fetching data:
```
┌─────────────────────────────────────────────────┐
│                                                 │
│              ⟳ Loading...                       │
│         Loading health data...                  │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Empty State

When no data available:
```
┌─────────────────────────────────────────────────┐
│                                                 │
│              ❤️                                  │
│         No Health Data                          │
│   No health data available for Dec 25, 2024    │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Testing Checklist

### Mac Side
- [ ] Date picker shows today by default
- [ ] Can select any past date
- [ ] Cannot select future dates
- [ ] Previous day button works
- [ ] Next day button works
- [ ] Next day button disabled for today
- [ ] Today button appears when not today
- [ ] Today button hidden when today
- [ ] Refresh button rotates when loading
- [ ] Loading indicator shows while fetching
- [ ] Data only displays if date matches

### Android Side
- [ ] Receives requestHealthSummary with date
- [ ] Parses date parameter correctly
- [ ] Fetches data for correct date range
- [ ] Aggregates data correctly
- [ ] Sends response with correct date
- [ ] Handles missing data gracefully
- [ ] Logs date being fetched

### Integration
- [ ] Selecting date triggers request
- [ ] Android responds with correct date's data
- [ ] Mac displays data for selected date
- [ ] Changing date updates display
- [ ] Loading state shows during fetch
- [ ] Empty state shows when no data

## Performance Considerations

### Caching Strategy

Consider caching fetched data to avoid repeated requests:

```kotlin
class HealthDataCache {
    private val cache = mutableMapOf<String, HealthSummary>()
    
    fun get(date: Date): HealthSummary? {
        val key = formatDateKey(date)
        return cache[key]
    }
    
    fun put(date: Date, summary: HealthSummary) {
        val key = formatDateKey(date)
        cache[key] = summary
        
        // Limit cache size
        if (cache.size > 30) {
            val oldestKey = cache.keys.first()
            cache.remove(oldestKey)
        }
    }
    
    private fun formatDateKey(date: Date): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return sdf.format(date)
    }
}
```

### Optimization Tips

1. **Cache recent dates**: Store last 30 days of data
2. **Batch requests**: If user rapidly changes dates, debounce requests
3. **Background fetch**: Fetch data in background thread
4. **Incremental loading**: Load basic metrics first, detailed data later
5. **Prefetch**: Fetch yesterday and tomorrow when viewing today

## Error Handling

### No Data Available

```kotlin
if (summary.steps == null && summary.calories == null && summary.distance == null) {
    // Send empty summary with date
    sendHealthSummary(createEmptySummary(date))
}
```

### Permission Denied

```kotlin
try {
    val summary = aggregateHealthData(startTime, endTime)
    sendHealthSummary(summary)
} catch (e: SecurityException) {
    Log.e(TAG, "Health Connect permission denied", e)
    sendError("Permission denied. Please grant Health Connect permissions.")
}
```

### Health Connect Not Available

```kotlin
if (!HealthConnectClient.isAvailable(context)) {
    Log.e(TAG, "Health Connect not available on this device")
    sendError("Health Connect is not available on this device")
    return
}
```

## Future Enhancements

1. **Date Range Selector**: Select start and end dates
2. **Week View**: Show aggregated data for entire week
3. **Month View**: Show monthly trends and averages
4. **Year View**: Show yearly progress
5. **Comparison**: Compare two dates side by side
6. **Trends**: Show graphs and trends over time
7. **Goals**: Set and track daily/weekly goals
8. **Export**: Export health data to CSV/PDF

## Summary

The date-based health data viewer is now complete on the Mac side. Users can:
- ✅ Select any past date with date picker
- ✅ Navigate between dates with arrow buttons
- ✅ Jump to today with one click
- ✅ See loading state while fetching
- ✅ View data only for selected date
- ✅ Refresh data on demand

Android side needs to:
- ⏳ Parse date parameter from request
- ⏳ Fetch health data for specific date range
- ⏳ Send response with correct date
- ⏳ Handle edge cases (no data, permissions, etc.)
