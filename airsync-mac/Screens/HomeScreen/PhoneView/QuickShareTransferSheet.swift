import SwiftUI
import AppKit
import Foundation

@MainActor
struct QuickShareTransferSheet: View {
    @ObservedObject var manager = QuickShareManager.shared
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: NSVisualEffectView.Material.hudWindow, blendingMode: NSVisualEffectView.BlendingMode.behindWindow)
                .edgesIgnoringSafeArea(Edge.Set.all)
            
            VStack(spacing: 20) {

                if manager.transferState == .discovering {
                    VStack(alignment: .leading, spacing: 10) {
                        if let targetName = manager.autoTargetDeviceName {
                            // Special Auto-Targeting UI for Menubar/Drop
                            VStack(spacing: 20) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(format: Localizer.shared.text("quickshare.waiting_for"), targetName))
                                            .font(.subheadline).bold()
                                        Text(Localizer.shared.text("quickshare.searching"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                
                                HStack(spacing: 12) {
                                    GlassButtonView(label: Localizer.shared.text("quickshare.more_devices"), size: .regular) {
                                        manager.autoTargetDeviceName = nil
                                    }
                                    
                                    GlassButtonView(label: Localizer.shared.text("quickshare.cancel"), size: .regular) {
                                        manager.stopDiscovery()
                                        appState.showingQuickShareTransfer = false
                                    }
                                }
                            }
                            // .frame(minHeight: 150)
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
                                    // .frame(minHeight: 150)
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
                            
                            GlassButtonView(label: Localizer.shared.text("quickshare.cancel"), size: .large) {
                                manager.stopDiscovery()
                                appState.showingQuickShareTransfer = false
                            }
                        }
                    }
                } else {
                    transferStatusView
                }
            }
            .padding(20)
        }

        .frame(minWidth: 350)
        .animation(.default, value: manager.transferState)
    }

    private var transferStatusView: some View {
        VStack(spacing: 15) {
            
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
            } else if case .receiving = manager.transferState {
                VStack(spacing: 8) {
                    Text(Localizer.shared.text("quickshare.receiving"))
                        .font(.headline)
                    ProgressView(value: manager.transferProgress)
                    Text("\(Int(manager.transferProgress * 100))%")
                        .font(.caption)
                }
            } else if case .incomingAwaitingConsent(let metadata, let device) = manager.transferState {
                VStack(spacing: 15) {
                    VStack(spacing: 5) {
                        Image(systemName: iconForDeviceType(device.type))
                            .font(.system(size: 40))
                            .padding(.bottom, 5)
                        Text(device.name)
                            .font(.subheadline).bold()
                        
                        let fileStr: String = {
                            if let textTitle = metadata.textDescription {
                                return textTitle
                            } else if metadata.files.count == 1 {
                                return metadata.files[0].name
                            } else {
                                return String(format: Localizer.shared.text("n_files"), metadata.files.count)
                            }
                        }()
                        
                        Text(fileStr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if let pin = metadata.pinCode {
                        Text(pin)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    HStack(spacing: 15) {
                        GlassButtonView(label: Localizer.shared.text("quickshare.decline"), size: .large) {
                            manager.handleUserConsent(transferID: metadata.id, accepted: false)
                        }
                        .foregroundStyle(.red)
                        
                        GlassButtonView(label: Localizer.shared.text("quickshare.accept"), size: .large, primary: true) {
                            manager.handleUserConsent(transferID: metadata.id, accepted: true)
                        }
                        .foregroundStyle(.green)
                    }
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
            
            if manager.transferState == .finished {
                GlassButtonView(label: Localizer.shared.text("quickshare.done"), size: .large, primary: true) {
                    manager.stopDiscovery()
                    appState.showingQuickShareTransfer = false
                }
            } else if manager.transferState == .discovering {
                GlassButtonView(label: Localizer.shared.text("quickshare.cancel"), size: .large) {
                    manager.stopDiscovery()
                    appState.showingQuickShareTransfer = false
                }
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
