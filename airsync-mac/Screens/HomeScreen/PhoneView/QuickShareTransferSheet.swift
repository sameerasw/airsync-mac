import SwiftUI

@MainActor
struct QuickShareTransferSheet: View {
    @ObservedObject var manager = QuickShareManager.shared
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(Localizer.shared.text("quickshare.title"))
                    .font(.headline)
                Spacer()
                Button(action: { 
                    manager.stopDiscovery()
                    appState.showingQuickShareTransfer = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            if manager.transferState == .discovering {
                VStack(alignment: .leading, spacing: 10) {
                    if let targetName = manager.autoTargetDeviceName {
                        // Special Auto-Targeting UI for Menubar
                        VStack(spacing: 20) {
                            HStack {
                                Text(String(format: Localizer.shared.text("quickshare.waiting_for"), targetName))
                                    .font(.subheadline)
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                            
                            HStack(spacing: 12) {
                                GlassButtonView(label: Localizer.shared.text("quickshare.more_devices")) {
                                    manager.autoTargetDeviceName = nil
                                }
                                
                                GlassButtonView(label: Localizer.shared.text("quickshare.cancel")) {
                                    manager.stopDiscovery()
                                    appState.showingQuickShareTransfer = false
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        // Default Device Selection UI
                        HStack {
                            Text(Localizer.shared.text("quickshare.select_device"))
                                .font(.subheadline)
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        if manager.discoveredDevices.isEmpty {
                            Text(Localizer.shared.text("quickshare.searching"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(manager.discoveredDevices, id: \.id) { device in
                                        Button(action: { 
                                            manager.sendFiles(urls: manager.transferURLs, to: device) 
                                        }) {
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
                        
                        Button(Localizer.shared.text("quickshare.cancel")) {
                            manager.stopDiscovery()
                            appState.showingQuickShareTransfer = false
                        }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } else {
                transferStatusView
            }
        }
        .padding(20)
        .frame(width: 350)
        .animation(.default, value: manager.transferState)
    }

    private var transferStatusView: some View {
        VStack(spacing: 15) {
            if manager.transferState != QuickShareManager.TransferState.idle {
                Text(manager.transferState == QuickShareManager.TransferState.finished ? Localizer.shared.text("quickshare.finished") : Localizer.shared.text("quickshare.sending"))
                    .font(.headline)
            }
            
            if case .awaitingPin(let pin) = manager.transferState {
                VStack(spacing: 5) {
                    Text(Localizer.shared.text("quickshare.confirm_pin"))
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
                    Text(Localizer.shared.text("quickshare.finished"))
                        .font(.headline)
                }
            } else if case .failed(let error) = manager.transferState {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(Localizer.shared.text("quickshare.failed"))
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if manager.transferState != .finished {
                Button(Localizer.shared.text("quickshare.cancel")) {
                    manager.stopDiscovery()
                    appState.showingQuickShareTransfer = false
                }
                .buttonStyle(.bordered)
            } else {
                Button(Localizer.shared.text("quickshare.done")) {
                    manager.stopDiscovery()
                    appState.showingQuickShareTransfer = false
                }
                .buttonStyle(.borderedProminent)
            }
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
