import SwiftUI

struct DeviceCard: View {
    let device: DiscoveredDevice
    let isLastConnected: Bool
    let isCompact: Bool
    let connectAction: () -> Void
    let namespace: Namespace.ID

    var body: some View {
        if isCompact {
            // Compact Mode
            Button(action: connectAction) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 16))
                        .matchedGeometryEffect(id: "icon-\(device.id)", in: namespace)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .matchedGeometryEffect(id: "name-\(device.id)", in: namespace)
                    }
                    
                    if !device.isActive {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    
                    HStack(spacing: 4) {
                        if device.ips.contains(where: { !$0.hasPrefix("100.") }) {
                            Image(systemName: "wifi")
                                .font(.system(size: 10))
                        }
                        if device.ips.contains(where: { $0.hasPrefix("100.") }) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(.secondary)
                    
                    if isLastConnected && device.isActive {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .matchedGeometryEffect(id: "status-\(device.id)", in: namespace)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassBoxIfAvailable(radius: 20)
                .tint(isLastConnected && device.isActive ? Color.accentColor.opacity(0.5) : Color.clear)
                .opacity(device.isActive ? 1.0 : 0.7)
                .grayscale(device.isActive ? 0 : 0.4)
            }
            .buttonStyle(.plain)
        } else {
            // Expanded Mode
            VStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                    .padding(.top, 16)
                    .matchedGeometryEffect(id: "icon-\(device.id)", in: namespace)
                
                VStack(spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                        .matchedGeometryEffect(id: "name-\(device.id)", in: namespace)
                    
                    HStack(spacing: 8) {
                        if device.ips.contains(where: { !$0.hasPrefix("100.") }) {
                                Image(systemName: "wifi")
                        }
                        if device.ips.contains(where: { $0.hasPrefix("100.") }) {
                                Image(systemName: "globe")
                        }


                        // Show primary IP
                        let displayIP = device.ips.first(where: { !$0.hasPrefix("100.") }) ?? device.ips.first ?? ""
                        Text(displayIP)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                }
                
                if isLastConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Last connected")
                    }
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: .capsule)
                    .matchedGeometryEffect(id: "status-\(device.id)", in: namespace)
                }
                
                Spacer()
                
                GlassButtonView(
                    label: "Connect",
                    systemImage: "bolt.circle.fill",
                    primary: device.isActive,
                    action: connectAction
                )
                .frame(maxWidth: .infinity)
                
                if !device.isActive {
                    Text("Recently seen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(16)
            .frame(width: 220, height: 240)
            .glassBoxIfAvailable(radius: 20)
            .opacity(device.isActive ? 1.0 : 0.7)
            .grayscale(device.isActive ? 0 : 0.4)
        }
    }
}
