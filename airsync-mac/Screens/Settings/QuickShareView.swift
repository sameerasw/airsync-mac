import SwiftUI

@MainActor
struct QuickShareView: View {
    @ObservedObject var manager = QuickShareManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedURLs: [URL] = []

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(Localizer.shared.text("quickshare.title"))
                    .font(.headline)
                Spacer()
                Button(action: { 
                    manager.stopDiscovery()
                    dismiss() 
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            Toggle(isOn: $manager.isEnabled) {
                VStack(alignment: .leading) {
                    Text(Localizer.shared.text("quickshare.settings.enabled"))
                        .font(.body)
                    if manager.isEnabled {
                        Text(String(format: Localizer.shared.text("quickshare.settings.discoverable"), manager.deviceName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)

            Divider()

            if manager.isEnabled {
                if manager.transferState == .idle {
                    VStack(spacing: 15) {
                        Label(Localizer.shared.text("quickshare.ready"), systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: selectFilesAndDiscover) {
                            Label("Send Files", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else if manager.transferState == .discovering {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Select a device")
                                .font(.subheadline)
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        if manager.discoveredDevices.isEmpty {
                            Text("Searching for nearby devices...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(manager.discoveredDevices, id: \.id) { device in
                                        Button(action: { manager.sendFiles(urls: selectedURLs, to: device) }) {
                                            HStack {
                                                Image(systemName: iconForDeviceType(device.type))
                                                    .frame(width: 24)
                                                Text(device.name)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(10)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                        
                        Button("Cancel") {
                            manager.stopDiscovery()
                        }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    transferStatusView
                }
            } else {
                Text("Quick Share is disabled. You won't be able to receive or send files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 350, height: manager.transferState == .idle ? 250 : 400)
        .animation(.default, value: manager.transferState)
    }

    private var transferStatusView: some View {
        VStack(spacing: 15) {
            Text("Sending...")
                .font(.headline)
            
            if case .awaitingPin(let pin) = manager.transferState {
                VStack(spacing: 5) {
                    Text("Confirm PIN on your device")
                        .font(.subheadline)
                    Text(pin)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                }
            } else if manager.transferState == .sending {
                VStack(spacing: 8) {
                    ProgressView(value: manager.transferProgress)
                    Text("\(Int(manager.transferProgress * 100))%")
                        .font(.caption)
                }
            } else if manager.transferState == .finished {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Transfer Finished!")
                        .font(.headline)
                }
            } else if case .failed(let error) = manager.transferState {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("Transfer Failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if manager.transferState != .finished {
                Button("Cancel") {
                    manager.stopDiscovery()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Done") {
                    manager.stopDiscovery()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func selectFilesAndDiscover() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            selectedURLs = panel.urls
            manager.startDiscovery()
        }
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
