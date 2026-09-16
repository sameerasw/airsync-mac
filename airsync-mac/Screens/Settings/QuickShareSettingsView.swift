import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var displayString: String = GlobalHotkeyManager.shared.shortcutDisplayString

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press a key combo…" : displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .secondary : .primary)
                .frame(minWidth: 110, alignment: .trailing)
            Button(isRecording ? "Cancel" : "Change") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore a bare Escape with no modifiers - treat it as "cancel recording".
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stopRecording()
                return nil
            }
            GlobalHotkeyManager.shared.keyCode = event.keyCode
            GlobalHotkeyManager.shared.modifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            GlobalHotkeyManager.shared.registerIfNeeded()
            displayString = GlobalHotkeyManager.shared.shortcutDisplayString
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

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
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                SettingsHeaderView(title: "Shared File Popup", icon: "doc.on.doc")
                VStack {
                    HStack {
                        Label(Localizer.shared.text("quickshare.settings.popupSharedImages"), systemImage: "doc.on.doc")
                        Spacer()
                        Toggle("", isOn: $appState.popupSharedImages)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label("Show summoned files", systemImage: "sparkles.rectangle.stack")
                        Spacer()
                        Toggle("", isOn: $appState.showSummonedFiles)
                            .toggleStyle(.switch)
                    }
                    Text("Also show this popup when a file is pulled from your phone using Summon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

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
                        .padding(.top, 4)
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
                .padding()
                .glassBoxIfAvailable(radius: 18)

                SettingsHeaderView(title: "Summon", icon: "sparkles.rectangle.stack")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Screenshot shortcut", systemImage: "keyboard")
                        Spacer()
                        HotkeyRecorderView()
                    }

                    Text("Pulls a screenshot from your phone and copies it to the clipboard. Currently requires an active ADB connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
