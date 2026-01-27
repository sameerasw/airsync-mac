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
                    
                    if isLastConnected {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .matchedGeometryEffect(id: "status-\(device.id)", in: namespace)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassBoxIfAvailable(radius: 20)
                .tint(isLastConnected ? Color.accentColor.opacity(0.2) : Color.clear)
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
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1), in: .capsule)
                    .matchedGeometryEffect(id: "status-\(device.id)", in: namespace)
                }
                
                GlassButtonView(
                    label: "Connect",
                    systemImage: "bolt.circle.fill",
                    primary: true,
                    action: connectAction
                )
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(width: 220, height: 220)
            .glassBoxIfAvailable(radius: 20)
        }
    }
}
