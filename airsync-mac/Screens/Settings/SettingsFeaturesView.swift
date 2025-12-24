//
//  SettingsFeaturesView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-04.
//

import SwiftUI
import UserNotifications

struct SettingsFeaturesView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("scrcpyShareRes") private var scrcpyShareRes = false
    @AppStorage("scrcpyOnTop") private var scrcpyOnTop = false
    @AppStorage("stayAwake") private var stayAwake = false
    @AppStorage("turnScreenOff") private var turnScreenOff = false
    @AppStorage("noAudio") private var noAudio = false
    @AppStorage("manualPosition") private var manualPosition = false
    @AppStorage("continueApp") private var continueApp = false
    @AppStorage("directKeyInput") private var directKeyInput = true

    @State private var showingPlusPopover = false
    @State private var tempBitrate: Double = 4.00
    @State private var tempResolution: Double = 1200.00
    @State private var isDragging = false
    @State private var xCoords: String = "0"
    @State private var yCoords: String = "0"

    // New state for notification permissions
    @State private var notificationsGranted = false
    @State private var notificationsChecked = false

    @State var isExpanded = false

    var body: some View {
        VStack{
            ZStack{
                HStack {
                    Label("Auto connect ADB", systemImage: "bolt.horizontal.circle")
                    Spacer()

                    if appState.adbConnected {
                        GlassButtonView(
                            label: "Disconnect ADB",
                            systemImage: "stop.circle",
                            action: {
                                ADBConnector.disconnectADB()
                                appState.adbConnected = false
                            }
                        )

                    } else {
                        GlassButtonView(
                            label: appState.adbConnecting ? "Connecting..." : "Connect ADB",
                            systemImage: appState.adbConnecting ? "hourglass" : "play.circle",
                            action: {
                                if !appState.adbConnecting {
                                    let ip = appState.device?.ipAddress ?? ""
                                    ADBConnector.connectToADB(ip: ip)
                                }
                            }
                        )
                        .disabled(
                            appState.device == nil || (appState.device?.adbPorts.isEmpty ?? true) || appState.adbConnecting || !AppState.shared.isPlus
                        )
                    }


                    ZStack {
                        Toggle(
                            "",
                            isOn: $appState.adbEnabled
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)

                    }
                    .frame(width: 55)

                }

                // Transparent tap area on top to show popover even if disabled
                if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                    HStack{
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
            .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                PlusFeaturePopover(message: "Wireless ADB features are available in AirSync+")
                    .onTapGesture {
                        showingPlusPopover = false
                    }
            }


            if let result = appState.adbConnectionResult {
                VStack(alignment: .leading, spacing: 6) {
                    ExpandableLicenseSection(title: "ADB Console", content: "[" + (UserDefaults.standard.lastADBCommand ?? "[]") + "] " + result)
                }
                .transition(.opacity)
            }

            HStack {
                Label("Suppress failed messages", systemImage: "bell.slash")
                Spacer()
                Toggle("", isOn: $appState.suppressAdbFailureAlerts)
                    .toggleStyle(.switch)
            }

            // Show port field if ADB toggle is on
            if appState.isPlus, (appState.adbEnabled || appState.adbConnected){

                Spacer()

                HStack{
                    Label("App Mirroring", systemImage: "apps.iphone.badge.plus")
                    Spacer()
                    Toggle("", isOn: $appState.mirroringPlus)
                        .toggleStyle(.switch)
                }


                VStack{
                    DisclosureGroup(isExpanded: $isExpanded) {
                        VStack(spacing: 10){
                            Spacer()

                            HStack {
                                Text("Video bitrate")
                                Spacer()

                                Slider(
                                    value: $tempBitrate,
                                    in: 1...12,
                                    step: 1,
                                    onEditingChanged: { editing in
                                        if !editing {
                                            AppState.shared.scrcpyBitrate = Int(tempBitrate)
                                        }
                                        isDragging = editing
                                    }
                                )
                                .focusable(false)
                                .frame(maxWidth: 150)

                                Text("\(AppState.shared.scrcpyBitrate) Mbps")
                                    .monospacedDigit()
                                    .foregroundColor(isDragging ? .accentColor : .secondary)
                                    .frame(width: 60, alignment: .leading)
                            }

                            HStack {
                                Text("Max size")
                                Spacer()

                                Slider(
                                    value: $tempResolution,
                                    in: 800...2600,
                                    step: 200,
                                    onEditingChanged: { editing in
                                        if !editing {
                                            AppState.shared.scrcpyResolution = Int(
                                                tempResolution
                                            )
                                        }
                                        isDragging = editing
                                    }
                                )
                                .focusable(false)
                                .frame(maxWidth: 150)

                                Text("\(AppState.shared.scrcpyResolution)")
                                    .monospacedDigit()
                                    .foregroundColor(isDragging ? .accentColor : .secondary)
                                    .frame(width: 60, alignment: .leading)
                            }

                            SettingsToggleView(name: "Stay on top", icon: "inset.filled.toptrailing.rectangle.portrait", isOn: $scrcpyOnTop)

                            SettingsToggleView(name: "Stay awake (charging)", icon: "cup.and.heat.waves", isOn: $stayAwake)

                            SettingsToggleView(name: "Blank display", icon: "iphone.gen3.slash", isOn: $turnScreenOff)

                            SettingsToggleView(name: "No audio", icon: "speaker.slash", isOn: $noAudio)

                            SettingsToggleView(name: "Continue app after closing", icon: "arrow.turn.up.forward.iphone", isOn: $continueApp)

                            SettingsToggleView(name: "Direct keyboard input", icon: "keyboard.chevron.compact.down", isOn: $directKeyInput)

                            SettingsToggleView(name: "Apps & Desktop mode shared resolution", icon: "ipad.sizes", isOn: $scrcpyShareRes)

                            HStack {
                                Text(UserDefaults.standard.scrcpyShareRes ? "Desktop and App mirroring" :"Desktop mode")
                                Spacer()

                                Picker("", selection: Binding(
                                    get: { UserDefaults.standard.scrcpyDesktopMode },
                                    set: { UserDefaults.standard.scrcpyDesktopMode = $0 }
                                )) {
                                    Text("2560x1440").tag("2560x1440")
                                    Text("2560x1600").tag("2560x1600")
                                    Text("2000x1800").tag("2000x1800")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }

                            HStack{
                                Text("Manual launch position (x,y)")
                                Spacer()

                                TextField("x", text: $xCoords)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: xCoords) { oldValue, newValue in
                                        xCoords = newValue.filter { "0123456789".contains($0) }
                                    }
                                    .disabled(
                                        !manualPosition
                                    )

                                TextField("y", text: $yCoords)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: yCoords) { oldValue, newValue in
                                        yCoords = newValue.filter { "0123456789".contains($0) }
                                    }
                                    .disabled(
                                        !manualPosition
                                    )

                                GlassButtonView(
                                    label: "Set",
                                    action: {
                                        UserDefaults.standard.manualPositionCoords = [xCoords, yCoords]
                                    }
                                )
                                .disabled(
                                    xCoords.isEmpty || yCoords.isEmpty || !manualPosition
                                )

                                Toggle("", isOn: $manualPosition)
                                    .toggleStyle(.switch)
                            }
                        }
                    } label: {
                        Label("Mirroring Settings", systemImage: "gear")
                            .font(.subheadline)
                            .bold()
                    }
                    .onAppear {
                        tempBitrate = Double(AppState.shared.scrcpyBitrate)
                        tempResolution = Double(AppState.shared.scrcpyResolution)
                    }
                    .focusEffectDisabled()

                }
            }

        }
        .padding()
        .onAppear{
            xCoords = UserDefaults.standard.manualPositionCoords[0]
            yCoords = UserDefaults.standard.manualPositionCoords[1]
        }


        VStack{

            SettingsToggleView(name: "Sync clipboard", icon: "clipboard", isOn: $appState.isClipboardSyncEnabled)

            HStack {
                Label("Auto-open shared links", systemImage: "link")
                Spacer()
                Toggle("", isOn: $appState.autoOpenLinks)
                    .toggleStyle(.switch)
                    .disabled(!appState.isClipboardSyncEnabled)
            }
            .opacity(appState.isClipboardSyncEnabled ? 1.0 : 0.5)
        }
        .padding()

        VStack{

            SettingsToggleView(name: "Sync notification dismissals", icon: "bell.badge", isOn: $appState.dismissNotif)

            HStack {
                Label("System Notifications", systemImage: "bell.badge")

                Spacer()

                if notificationsGranted {
                    // Show sound picker when notifications are enabled
                    Picker("", selection: $appState.notificationSound) {
                        Text("Default").tag("default")
                        ForEach(SystemSounds.availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(minWidth: 100)

                    Button(action: {
                        SystemSounds.playSound(appState.notificationSound)
                    }) {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Test notification sound")
                } else {
                    // Show enable button when notifications are not granted
                    GlassButtonView(
                        label: "Grant Permission",
                        systemImage: "bell.badge",
                        primary: true,
                        action: {
                            openNotificationSettings()
                        }
                    )
                }
            }

            SettingsToggleView(name: "Send now playing status", icon: "play.circle", isOn: $appState.sendNowPlayingStatus)
        }
        .padding()
        .onAppear{
            checkNotificationPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh notification permissions when app becomes active
            // This helps update the UI when user returns from System Preferences
            checkNotificationPermissions()
        }

        VStack{

            HStack {
                Label("Call Alert", systemImage: "phone")
                Spacer()

                Picker("", selection: $appState.callNotificationMode) {
                    ForEach(CallNotificationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(minWidth: 120)
            }

            SettingsToggleView(name: "Ring for calls", icon: "speaker.wave.3", isOn: $appState.ringForCalls)
        }
        .padding()
    }

    // MARK: - Notification Permission Helpers
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = (settings.authorizationStatus == .authorized)
                notificationsChecked = true
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
