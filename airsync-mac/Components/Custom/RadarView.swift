//
//  RadarView.swift
//  airsync-mac
//
//  Created by AI Assistant on 2026-03-12.
//

import SwiftUI

struct RadarView: View {
    let devices: [RemoteDeviceInfo]
    let onDeviceSelected: (RemoteDeviceInfo) -> Void
    
    @State private var animateCircles = false
    
    var body: some View {
        ZStack {
            // Animated concentric circles
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(1), lineWidth: 4)
                    .scaleEffect(animateCircles ? 1.0 : 0.0)
                    .opacity(animateCircles ? 0.0 : 1.0)
                
                Circle()
                    .stroke(Color.accentColor.opacity(1), lineWidth: 4)
                    .scaleEffect(animateCircles ? 1.0 : 0.0)
                    .opacity(animateCircles ? 0.0 : 0.8)
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false).delay(1), value: animateCircles)
                
                Circle()
                    .stroke(Color.accentColor.opacity(1), lineWidth: 4)
                    .scaleEffect(animateCircles ? 1.0 : 0.0)
                    .opacity(animateCircles ? 0.0 : 0.6)
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false).delay(2), value: animateCircles)
            }
            .frame(width: 250, height: 250) // Constrain circles to center
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    animateCircles = true
                }
            }
            
            // Central "Self" node with Glass effect
            GlassBoxView(width: 44, height: 44, radius: 22)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                )
            
            // Discovered devices far away
            ForEach(devices, id: \.id) { device in
                // Find index to calculate position
                let index = devices.firstIndex(where: { $0.id == device.id }) ?? 0
                DeviceNodeView(device: device, index: index, total: devices.count) {
                    onDeviceSelected(device)
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale(scale: 0.1).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .animation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0.5), value: devices)
    }
}

struct DeviceNodeView: View {
    let device: RemoteDeviceInfo
    let index: Int
    let total: Int
    let action: () -> Void
    
    var body: some View {
        let angle = Double(index) * (2.0 * .pi / Double(max(total, 1)))
        let radius: CGFloat = 100 // Increased orbital distance
        let x = cos(angle) * radius
        let y = sin(angle) * radius
        
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    GlassBoxView(width: 70, height: 70, radius: 35) // Bigger node
                        .overlay(
                            Image(systemName: iconForDeviceType(device.type))
                                .font(.system(size: 28)) // Bigger icon
                        )
                }
                
                Text(device.name)
                    .font(.caption)
                    .bold()
                    .lineLimit(2) // Support 2 lines
                    .multilineTextAlignment(.center)
                    .frame(width: 90)
            }
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
    }
    
    private func iconForDeviceType(_ type: RemoteDeviceInfo.DeviceType) -> String {
        switch type {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .computer: return "macbook"
        default: return "questionmark.circle"
        }
    }
}
