//
//  ModernHealthView.swift
//  airsync-mac
//
//  Modern glassmorphic health view
//

import SwiftUI

struct HealthView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    @State private var selectedDate = Date()
    @State private var isLoadingData = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Date Picker Header
            HStack(spacing: 12) {
                // Previous Day Button
                Button(action: { changeDate(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Previous Day")
                
                // Date Picker
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: selectedDate) { _, newDate in
                    requestHealthData(for: newDate)
                }
                
                // Next Day Button (disabled if today)
                Button(action: { changeDate(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1.0)
                .help("Next Day")
                
                Spacer()
                
                // Today Button
                if !Calendar.current.isDateInToday(selectedDate) {
                    Button("Today") {
                        selectedDate = Date()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // Refresh Button
                Button(action: { requestHealthData(for: selectedDate) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .rotationEffect(.degrees(isLoadingData ? 360 : 0))
                        .animation(isLoadingData ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingData)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding()
            .background(.background.opacity(0.5))
            
            Divider()
            
            // Health Data Content
            ScrollView {
                if let summary = manager.healthSummary {
                    let summaryDateStr = formatDate(summary.date)
                    let selectedDateStr = formatDate(selectedDate)
                    let datesMatch = isSameDay(summary.date, selectedDate)
                    let _ = print("[health-view] 📅 Date comparison: summary=\(summaryDateStr), selected=\(selectedDateStr), match=\(datesMatch)")
                    
                    if datesMatch {
                        let _ = print("[health-view] 📊 Rendering health data: steps=\(summary.steps ?? 0)")
                        LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        // Steps
                        if let steps = summary.steps {
                            HealthMetricCard(
                                icon: "figure.walk",
                                title: "Steps",
                                value: "\(steps)",
                                subtitle: "of 10,000",
                                progress: summary.stepsProgress,
                                color: .blue
                            )
                        }
                        
                        // Calories
                        if let calories = summary.calories {
                            HealthMetricCard(
                                icon: "flame.fill",
                                title: "Calories",
                                value: "\(calories)",
                                subtitle: "kcal",
                                progress: summary.caloriesProgress,
                                color: .orange
                            )
                        }
                        
                        // Distance
                        if let distance = summary.distance {
                            HealthMetricCard(
                                icon: "location.fill",
                                title: "Distance",
                                value: String(format: "%.1f", distance),
                                subtitle: "km",
                                progress: nil,
                                color: .green
                            )
                        }
                        
                        // Heart Rate
                        if let heartRate = summary.heartRateAvg {
                            HealthMetricCard(
                                icon: "heart.fill",
                                title: "Heart Rate",
                                value: "\(heartRate)",
                                subtitle: "bpm",
                                progress: nil,
                                color: .red
                            )
                        }
                        
                        // Sleep
                        if let sleep = summary.sleepDuration {
                            let hours = sleep / 60
                            let minutes = sleep % 60
                            HealthMetricCard(
                                icon: "bed.double.fill",
                                title: "Sleep",
                                value: "\(hours)h \(minutes)m",
                                subtitle: "of 8h",
                                progress: Double(sleep) / 480.0,
                                color: .purple
                            )
                        }
                        
                        // Active Minutes
                        if let activeMinutes = summary.activeMinutes {
                            HealthMetricCard(
                                icon: "figure.run",
                                title: "Active",
                                value: "\(activeMinutes)",
                                subtitle: "minutes",
                                progress: nil,
                                color: .cyan
                            )
                        }
                        
                        // Additional Health Metrics
                        if let floors = summary.floorsClimbed {
                            HealthMetricCard(
                                icon: "stairs",
                                title: "Floors",
                                value: "\(floors)",
                                subtitle: "climbed",
                                progress: nil,
                                color: .brown
                            )
                        }
                        
                        if let weight = summary.weight {
                            HealthMetricCard(
                                icon: "scalemass.fill",
                                title: "Weight",
                                value: String(format: "%.1f", weight),
                                subtitle: "kg",
                                progress: nil,
                                color: .indigo
                            )
                        }
                        
                        if let systolic = summary.bloodPressureSystolic,
                           let diastolic = summary.bloodPressureDiastolic {
                            HealthMetricCard(
                                icon: "heart.circle.fill",
                                title: "Blood Pressure",
                                value: "\(systolic)/\(diastolic)",
                                subtitle: "mmHg",
                                progress: nil,
                                color: .red
                            )
                        }
                        
                        if let oxygen = summary.oxygenSaturation {
                            HealthMetricCard(
                                icon: "lungs.fill",
                                title: "Oxygen",
                                value: String(format: "%.1f%%", oxygen),
                                subtitle: "SpO2",
                                progress: oxygen / 100.0,
                                color: .mint
                            )
                        }
                        
                        if let restingHR = summary.restingHeartRate {
                            HealthMetricCard(
                                icon: "heart.text.square.fill",
                                title: "Resting HR",
                                value: "\(restingHR)",
                                subtitle: "bpm",
                                progress: nil,
                                color: .pink
                            )
                        }
                        
                        if let vo2 = summary.vo2Max {
                            HealthMetricCard(
                                icon: "figure.strengthtraining.traditional",
                                title: "VO2 Max",
                                value: String(format: "%.1f", vo2),
                                subtitle: "ml/kg/min",
                                progress: nil,
                                color: .teal
                            )
                        }
                        
                        if let temp = summary.bodyTemperature {
                            HealthMetricCard(
                                icon: "thermometer.medium",
                                title: "Temperature",
                                value: String(format: "%.1f°C", temp),
                                subtitle: "body temp",
                                progress: nil,
                                color: .yellow
                            )
                        }
                        
                        if let glucose = summary.bloodGlucose {
                            HealthMetricCard(
                                icon: "drop.fill",
                                title: "Blood Glucose",
                                value: String(format: "%.1f", glucose),
                                subtitle: "mg/dL",
                                progress: nil,
                                color: .purple
                            )
                        }
                        
                        if let hydration = summary.hydration {
                            HealthMetricCard(
                                icon: "drop.circle.fill",
                                title: "Hydration",
                                value: String(format: "%.1f", hydration),
                                subtitle: "liters",
                                progress: hydration / 3.0, // 3L daily goal
                                color: .blue
                            )
                        }
                        }
                        .padding()
                    } else {
                        // Dates don't match - show warning with data
                        VStack(spacing: 16) {
                            // Warning banner
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Android sent data for \(summaryDateStr) instead of \(selectedDateStr)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            
                            // Show the data anyway (for debugging)
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                // Steps
                                if let steps = summary.steps {
                                    HealthMetricCard(
                                        icon: "figure.walk",
                                        title: "Steps",
                                        value: "\(steps)",
                                        subtitle: "of 10,000",
                                        progress: summary.stepsProgress,
                                        color: .blue
                                    )
                                }
                                
                                // Calories
                                if let calories = summary.calories {
                                    HealthMetricCard(
                                        icon: "flame.fill",
                                        title: "Calories",
                                        value: "\(calories)",
                                        subtitle: "kcal",
                                        progress: summary.caloriesProgress,
                                        color: .orange
                                    )
                                }
                                
                                // Distance
                                if let distance = summary.distance {
                                    HealthMetricCard(
                                        icon: "location.fill",
                                        title: "Distance",
                                        value: String(format: "%.1f", distance),
                                        subtitle: "km",
                                        progress: nil,
                                        color: .green
                                    )
                                }
                                
                                // Heart Rate
                                if let heartRate = summary.heartRateAvg {
                                    HealthMetricCard(
                                        icon: "heart.fill",
                                        title: "Heart Rate",
                                        value: "\(heartRate)",
                                        subtitle: "bpm",
                                        progress: nil,
                                        color: .red
                                    )
                                }
                                
                                // Sleep
                                if let sleep = summary.sleepDuration {
                                    let hours = sleep / 60
                                    let minutes = sleep % 60
                                    HealthMetricCard(
                                        icon: "bed.double.fill",
                                        title: "Sleep",
                                        value: "\(hours)h \(minutes)m",
                                        subtitle: "of 8h",
                                        progress: Double(sleep) / 480.0,
                                        color: .purple
                                    )
                                }
                                
                                // Active Minutes
                                if let activeMinutes = summary.activeMinutes {
                                    HealthMetricCard(
                                        icon: "figure.run",
                                        title: "Active",
                                        value: "\(activeMinutes)",
                                        subtitle: "minutes",
                                        progress: nil,
                                        color: .cyan
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                } else {
                    let _ = print("[health-view] ⚠️ No health summary data available for \(formatDate(selectedDate))")
                    VStack(spacing: 16) {
                        if isLoadingData {
                            ProgressView()
                                .scaleEffect(1.5)
                                .padding()
                            Text("Loading health data...")
                                .foregroundColor(.secondary)
                        } else {
                            // Show placeholder cards with zero data
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                // Basic metrics with zero values
                                HealthMetricCard(
                                    icon: "figure.walk",
                                    title: "Steps",
                                    value: "0",
                                    subtitle: "of 10,000",
                                    progress: 0,
                                    color: .blue
                                )
                                
                                HealthMetricCard(
                                    icon: "flame.fill",
                                    title: "Calories",
                                    value: "0",
                                    subtitle: "kcal",
                                    progress: 0,
                                    color: .orange
                                )
                                
                                HealthMetricCard(
                                    icon: "location.fill",
                                    title: "Distance",
                                    value: "0.0",
                                    subtitle: "km",
                                    progress: nil,
                                    color: .green
                                )
                                
                                HealthMetricCard(
                                    icon: "heart.fill",
                                    title: "Heart Rate",
                                    value: "--",
                                    subtitle: "bpm",
                                    progress: nil,
                                    color: .red
                                )
                                
                                HealthMetricCard(
                                    icon: "bed.double.fill",
                                    title: "Sleep",
                                    value: "--",
                                    subtitle: "hours",
                                    progress: nil,
                                    color: .purple
                                )
                                
                                HealthMetricCard(
                                    icon: "figure.run",
                                    title: "Active",
                                    value: "0",
                                    subtitle: "minutes",
                                    progress: nil,
                                    color: .cyan
                                )
                            }
                            .padding()
                            
                            // Info message
                            Text("No health data available for \(formatDate(selectedDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding()
                }
                
                // Bottom spacer to prevent content from being hidden by DockTabBar
                Spacer(minLength: 100)
            }
        }
        .onAppear {
            print("[health-view] 📱 View appeared, requesting health summary for today")
            selectedDate = Date()
            requestHealthData(for: selectedDate)
        }
    }
    
    // MARK: - Helper Methods
    
    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func requestHealthData(for date: Date) {
        print("[health-view] 📅 Requesting health data for: \(formatDate(date))")
        isLoadingData = true
        
        // Request health data for specific date
        WebSocketServer.shared.requestHealthSummary(for: date)
        
        // Stop loading indicator after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isLoadingData = false
        }
    }
    
    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct HealthMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let progress: Double?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }
                
                Spacer()
            }
            
            // Value
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(min(progress, 1.0)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            
            // Title
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(height: 160)
        .background(.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
