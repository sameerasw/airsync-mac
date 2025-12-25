//
//  MirrorPerformanceOverlay.swift
//  airsync-mac
//
//  Performance monitoring overlay for mirror view
//

import SwiftUI
internal import Combine

struct MirrorPerformanceOverlay: View {
    @StateObject private var monitor = PerformanceMonitor.shared
    @State private var isVisible = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                if isVisible {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("FPS: \(monitor.currentFPS, specifier: "%.1f")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(fpsColor)
                        
                        Text("Latency: \(monitor.estimatedLatency)ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(latencyColor)
                        
                        Text("Frames: \(monitor.frameCount)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("Dropped: \(monitor.droppedFrames)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(monitor.droppedFrames > 0 ? .red : .secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .transition(.opacity)
                }
                
                Button(action: { withAnimation { isVisible.toggle() } }) {
                    Image(systemName: isVisible ? "chart.bar.fill" : "chart.bar")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding(10)
            
            Spacer()
        }
    }
    
    private var fpsColor: Color {
        if monitor.currentFPS >= 28 { return .green }
        if monitor.currentFPS >= 20 { return .orange }
        return .red
    }
    
    private var latencyColor: Color {
        if monitor.estimatedLatency < 150 { return .green }
        if monitor.estimatedLatency < 250 { return .orange }
        return .red
    }
}

class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var currentFPS: Double = 0
    @Published var estimatedLatency: Int = 0
    @Published var frameCount: Int = 0
    @Published var droppedFrames: Int = 0
    
    private var lastFrameTime: Date?
    private var frameTimes: [TimeInterval] = []
    private let maxFrameTimeSamples = 30
    
    private init() {
        // Start monitoring
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    func recordFrame() {
        let now = Date()
        
        if let last = lastFrameTime {
            let interval = now.timeIntervalSince(last)
            frameTimes.append(interval)
            
            // Keep only recent samples
            if frameTimes.count > maxFrameTimeSamples {
                frameTimes.removeFirst()
            }
            
            // Detect dropped frames (> 50ms gap = dropped frame at 30fps)
            if interval > 0.05 {
                droppedFrames += 1
            }
        }
        
        lastFrameTime = now
        frameCount += 1
    }
    
    private func updateMetrics() {
        guard !frameTimes.isEmpty else { return }
        
        // Calculate average FPS
        let avgInterval = frameTimes.reduce(0, +) / Double(frameTimes.count)
        currentFPS = avgInterval > 0 ? 1.0 / avgInterval : 0
        
        // Estimate latency (frame interval + network + processing)
        // Rough estimate: 2x frame time + 50ms base
        estimatedLatency = Int((avgInterval * 2000) + 50)
    }
    
    func reset() {
        frameCount = 0
        droppedFrames = 0
        frameTimes.removeAll()
        lastFrameTime = nil
    }
}
