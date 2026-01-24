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
                        // Steps - always show
                        HealthMetricCard(
                            icon: "figure.walk",
                            title: "Steps",
                            value: summary.steps != nil ? "\(summary.steps!)" : "0",
                            subtitle: "of 10,000",
                            progress: summary.stepsProgress,
                            color: .blue
                        )
                        
                        // Calories - always show
                        HealthMetricCard(
                            icon: "flame.fill",
                            title: "Calories",
                            value: summary.calories != nil ? "\(summary.calories!)" : "0",
                            subtitle: "kcal",
                            progress: summary.caloriesProgress,
                            color: .orange
                        )
                        
                        // Distance - always show
                        HealthMetricCard(
                            icon: "location.fill",
                            title: "Distance",
                            value: summary.distance != nil ? String(format: "%.1f", summary.distance!) : "0.0",
                            subtitle: "km",
                            progress: nil,
                            color: .green
                        )
                        
                        // Heart Rate - always show
                        HealthMetricCard(
                            icon: "heart.fill",
                            title: "Heart Rate",
                            value: summary.heartRateAvg != nil ? "\(summary.heartRateAvg!)" : "--",
                            subtitle: "bpm",
                            progress: nil,
                            color: .red
                        )
                        
                        // Sleep - always show
                        let sleepHours = (summary.sleepDuration ?? 0) / 60
                        let sleepMinutes = (summary.sleepDuration ?? 0) % 60
                        let sleepProgress = summary.sleepDuration != nil ? Double(summary.sleepDuration!) / 480.0 : 0
                        HealthMetricCard(
                            icon: "bed.double.fill",
                            title: "Sleep",
                            value: summary.sleepDuration != nil ? "\(sleepHours)h \(sleepMinutes)m" : "--",
                            subtitle: "of 8h",
                            progress: sleepProgress,
                            color: .purple
                        )
                        
                        // Active Minutes - always show
                        HealthMetricCard(
                            icon: "figure.run",
                            title: "Active",
                            value: summary.activeMinutes != nil ? "\(summary.activeMinutes!)" : "0",
                            subtitle: "minutes",
                            progress: nil,
                            color: .cyan
                        )
                        
                        // Floors - always show
                        HealthMetricCard(
                            icon: "stairs",
                            title: "Floors",
                            value: summary.floorsClimbed != nil ? "\(summary.floorsClimbed!)" : "0",
                            subtitle: "climbed",
                            progress: nil,
                            color: .brown
                        )
                        
                        // Weight - show if available
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
                        
                        // Blood Pressure - show if available
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
                        
                        // Oxygen - show if available
                        if let oxygen = summary.oxygenSaturation, oxygen > 0 {
                            let oxygenProgress = oxygen.isFinite ? oxygen / 100.0 : 0
                            HealthMetricCard(
                                icon: "lungs.fill",
                                title: "Oxygen",
                                value: String(format: "%.1f%%", oxygen),
                                subtitle: "SpO2",
                                progress: oxygenProgress,
                                color: .mint
                            )
                        }
                        
                        // Resting HR - show if available
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
                        
                        // VO2 Max - show if available
                        if let vo2 = summary.vo2Max, vo2 > 0 {
                            HealthMetricCard(
                                icon: "figure.strengthtraining.traditional",
                                title: "VO2 Max",
                                value: String(format: "%.1f", vo2),
                                subtitle: "ml/kg/min",
                                progress: nil,
                                color: .teal
                            )
                        }
                        
                        // Temperature - show if available
                        if let temp = summary.bodyTemperature, temp > 0 {
                            HealthMetricCard(
                                icon: "thermometer.medium",
                                title: "Temperature",
                                value: String(format: "%.1f°C", temp),
                                subtitle: "body temp",
                                progress: nil,
                                color: .yellow
                            )
                        }
                        
                        // Blood Glucose - show if available
                        if let glucose = summary.bloodGlucose, glucose > 0 {
                            HealthMetricCard(
                                icon: "drop.fill",
                                title: "Blood Glucose",
                                value: String(format: "%.1f", glucose),
                                subtitle: "mg/dL",
                                progress: nil,
                                color: .purple
                            )
                        }
                        
                        // Hydration - show if available
                        if let hydration = summary.hydration, hydration > 0 {
                            let hydrationProgress = hydration.isFinite ? hydration / 3.0 : 0
                            HealthMetricCard(
                                icon: "drop.circle.fill",
                                title: "Hydration",
                                value: String(format: "%.1f", hydration),
                                subtitle: "liters",
                                progress: hydrationProgress,
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
                                // Steps - always show
                                HealthMetricCard(
                                    icon: "figure.walk",
                                    title: "Steps",
                                    value: summary.steps != nil ? "\(summary.steps!)" : "0",
                                    subtitle: "of 10,000",
                                    progress: summary.stepsProgress,
                                    color: .blue
                                )
                                
                                // Calories - always show
                                HealthMetricCard(
                                    icon: "flame.fill",
                                    title: "Calories",
                                    value: summary.calories != nil ? "\(summary.calories!)" : "0",
                                    subtitle: "kcal",
                                    progress: summary.caloriesProgress,
                                    color: .orange
                                )
                                
                                // Distance - always show
                                HealthMetricCard(
                                    icon: "location.fill",
                                    title: "Distance",
                                    value: summary.distance != nil ? String(format: "%.1f", summary.distance!) : "0.0",
                                    subtitle: "km",
                                    progress: nil,
                                    color: .green
                                )
                                
                                // Heart Rate - always show
                                HealthMetricCard(
                                    icon: "heart.fill",
                                    title: "Heart Rate",
                                    value: summary.heartRateAvg != nil ? "\(summary.heartRateAvg!)" : "--",
                                    subtitle: "bpm",
                                    progress: nil,
                                    color: .red
                                )
                                
                                // Sleep - always show
                                let sleepHours2 = (summary.sleepDuration ?? 0) / 60
                                let sleepMinutes2 = (summary.sleepDuration ?? 0) % 60
                                let sleepProgress2 = summary.sleepDuration != nil ? Double(summary.sleepDuration!) / 480.0 : 0
                                HealthMetricCard(
                                    icon: "bed.double.fill",
                                    title: "Sleep",
                                    value: summary.sleepDuration != nil ? "\(sleepHours2)h \(sleepMinutes2)m" : "--",
                                    subtitle: "of 8h",
                                    progress: sleepProgress2,
                                    color: .purple
                                )
                                
                                // Active Minutes - always show
                                HealthMetricCard(
                                    icon: "figure.run",
                                    title: "Active",
                                    value: summary.activeMinutes != nil ? "\(summary.activeMinutes!)" : "0",
                                    subtitle: "minutes",
                                    progress: nil,
                                    color: .cyan
                                )
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
        
        // First check cache - this will also trigger a request if needed
        _ = manager.getHealthSummary(for: date)
        
        // Stop loading indicator after 3 seconds or when data arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isLoadingData = false
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
    
    // Safe progress value that guards against NaN and Infinity
    private var safeProgress: Double? {
        guard let p = progress else { return nil }
        guard p.isFinite else { return 0 }
        return min(max(p, 0), 1.0)
    }
    
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
            if let progress = safeProgress {
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
                            .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 6)
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
