import SwiftUI

struct DeviceCard: View {
    let device: DiscoveredDevice
    let isLastConnected: Bool
    let connectAction: () -> Void
    let namespace: Namespace.ID?

    @State private var wallpaperImage: NSImage?
    @ObservedObject private var quickConnectManager = QuickConnectManager.shared
    @ObservedObject private var bleManager = BLECentralManager.shared

    private var isLoading: Bool {
        if device.type == "ble" {
            return bleManager.connectingDeviceUUID == device.deviceId
        }
        return quickConnectManager.connectingDeviceID == device.id
    }

    var body: some View {
        Group {
            
                VStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                        .ifLet(namespace) { view, ns in
                            view.matchedGeometryEffect(id: "icon-\(device.id)", in: ns)
                        }
                    
                    VStack(spacing: 4) {
                        Text(device.name)
                            .font(.system(size: 18, weight: .bold))
                            .multilineTextAlignment(.center)
                            .ifLet(namespace) { view, ns in
                                view.matchedGeometryEffect(id: "name-\(device.id)", in: ns)
                            }
                        
                        HStack(spacing: 8) {
                            if device.type == "ble" {
                                Image("logo.bluetooth")
                                Text("Nearby")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                if device.ips.contains("Bluetooth LE") || device.ips.contains("Nearby") {
                                    Image("logo.bluetooth")
                                }
                                if device.ips.contains(where: { $0 != "Bluetooth LE" && $0 != "Nearby" && !$0.hasPrefix("100.") }) {
                                        Image(systemName: "wifi")
                                }
                                if device.ips.contains(where: { $0 != "Bluetooth LE" && $0 != "Nearby" && $0.hasPrefix("100.") }) {
                                        Image(systemName: "globe")
                                }

                                // Show primary IP excluding Bluetooth LE and Nearby
                                let displayIP = device.ips.first(where: { $0 != "Bluetooth LE" && $0 != "Nearby" && !$0.hasPrefix("100.") }) ?? device.ips.first(where: { $0 != "Bluetooth LE" && $0 != "Nearby" }) ?? ""
                                if !displayIP.isEmpty && displayIP != "Bluetooth LE" && displayIP != "Nearby" {
                                    HStack(spacing: 4) {
                                        Text(displayIP)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(device.discoverySource == .mdns ? "mDNS" : "UDP")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(device.discoverySource == .mdns ? .accentColor : .secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                (device.discoverySource == .mdns ? Color.accentColor : Color.secondary).opacity(0.15),
                                                in: RoundedRectangle(cornerRadius: 3)
                                            )
                                    }
                                    .transition(.opacity)
                                }
                            }
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
                        .ifLet(namespace) { view, ns in
                            view.matchedGeometryEffect(id: "status-\(device.id)", in: ns)
                        }
                    }
                    
                    Spacer()
                    
                    GlassButtonView(
                        label: isLastConnected ? "\(L("button.connect")) ⌘⏎" : L("button.connect"),
                        systemImage: "bolt.circle.fill",
                        primary: device.isActive,
                        isLoading: isLoading,
                        action: connectAction
                    )
                    .conditionalKeyboardShortcut(isEnabled: isLastConnected)
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
                .background(
                    GeometryReader { geometry in
                        if let nsImage = wallpaperImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: device.isActive ? 0 : 3)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
        }
        .onAppear {
            loadWallpaper()
        }
        .onChange(of: device.id) { _, _ in
            loadWallpaper()
        }
    }

    private func loadWallpaper() {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let wallpaperPath = appSupport.appendingPathComponent("Wallpapers").appendingPathComponent("\(device.id).jpg")
            if fileManager.fileExists(atPath: wallpaperPath.path) {
                if let image = NSImage(contentsOf: wallpaperPath) {
                    self.wallpaperImage = image
                } else {
                    self.wallpaperImage = nil
                }
            } else {
                self.wallpaperImage = nil
            }
        }
    }
}

fileprivate struct KeyboardShortcutModifier: ViewModifier {
    var isEnabled: Bool
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(.return, modifiers: .command)
        } else {
            content
        }
    }
}

extension View {
    fileprivate func conditionalKeyboardShortcut(isEnabled: Bool) -> some View {
        self.modifier(KeyboardShortcutModifier(isEnabled: isEnabled))
    }
}
