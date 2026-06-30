import SwiftUI

struct QuickShareSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeaderView(title: "Quick Share", icon: "laptopcomputer.and.arrow.down")
                VStack {
                    HStack {
                        Label(Localizer.shared.text("quickshare.title"), systemImage: "bolt.horizontal.circle")
                        Spacer()
                        Toggle("", isOn: $appState.quickShareEnabled)
                            .toggleStyle(.switch)
                    }

                    if appState.quickShareEnabled {
                        Text(String(format: Localizer.shared.text("quickshare.settings.discoverable"), QuickShareManager.shared.deviceName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Label(Localizer.shared.text("quickshare.settings.autoAccept"), systemImage: "checkmark.shield")
                            Spacer()
                            Toggle("", isOn: $appState.autoAcceptQuickShare)
                                .toggleStyle(.switch)
                        }

                        HStack {
                            Label(Localizer.shared.text("quickshare.settings.popupSharedImages"), systemImage: "doc.on.doc")
                            Spacer()
                            Toggle("", isOn: $appState.popupSharedImages)
                                .toggleStyle(.switch)
                        }

                        if appState.popupSharedImages {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(Localizer.shared.text("quickshare.settings.maxPopups"), systemImage: "square.3.stack.3d")
                                        .padding(.leading, 12)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Text("\(appState.sharedImagePopupsLimit)")
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        Slider(
                                            value: Binding(
                                                get: { Double(appState.sharedImagePopupsLimit) },
                                                set: { appState.sharedImagePopupsLimit = Int(round($0)) }
                                            ),
                                            in: 1...10,
                                            step: 1
                                        )
                                        .frame(width: 120)
                                    }
                                }
                            }
                            .padding(.bottom, 4)

                            HStack {
                                Label(Localizer.shared.text("quickshare.settings.popupSide"), systemImage: "macwindow.and.ipad.arrow.left")
                                    .padding(.leading, 12)
                                Spacer()
                                Picker("", selection: $appState.popupSharedImagesOnLeft) {
                                    Text(Localizer.shared.text("quickshare.settings.side.left")).tag(true)
                                    Text(Localizer.shared.text("quickshare.settings.side.right")).tag(false)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                SettingsHeaderView(title: Localizer.shared.text("settings.fileAccess.title"), icon: "folder.badge.gearshape")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            HStack {
                                Label(Localizer.shared.text("settings.fileAccess.enabled"), systemImage: "externaldrive")
                                Text("BETA")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                                Spacer()
                                Toggle("", isOn: $appState.isFileAccessEnabled)
                                    .toggleStyle(.switch)
                                    .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)
                            }

                            if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                                HStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showingPlusPopover = true
                                        }
                                        .frame(width: 500)
                                }
                            }
                        }
                    }
                    .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                        PlusFeaturePopover(message: "File Access feature is available in AirSync+")
                            .onTapGesture {
                                showingPlusPopover = false
                            }
                    }

                    Text(Localizer.shared.text("settings.fileAccess.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
    }
}
