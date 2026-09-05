import SwiftUI
import AppKit

struct MenubarSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false
    @State private var plusPopoverMessage = ""
    @State private var showMarqueeInfo = false
    @State private var isDraggingFontSize = false
    @State private var isDraggingTextLength = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeaderView(title: L("settings.menubar"), icon: "menubar.arrow.up.rectangle")
                VStack(spacing: 12) {
                    HStack {
                        Label(L("settings.menubar.fontSize"), systemImage: "textformat.size")
                        Spacer()
                        Slider(
                            value: $appState.menubarFontSize,
                            in: 10...16,
                            step: 1,
                            onEditingChanged: { editing in
                                isDraggingFontSize = editing
                                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                            }
                        )
                        .frame(width: 150)
                        .controlSize(.small)
                        .onChange(of: appState.menubarFontSize) { oldValue, newValue in
                            guard isDraggingFontSize else { return }
                            if newValue != oldValue {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                            }
                        }
                        
                        Text("\(Int(appState.menubarFontSize))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }

                    HStack {
                        Label(L("settings.menubar.showIcon"), systemImage: "iphone.gen3")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarIcon)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label(L("settings.menubar.showText"), systemImage: "text.alignleft")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarText)
                            .toggleStyle(.switch)
                    }

                    VStack(spacing: 12) {
                        HStack {
                            Label(L("settings.menubar.maxLength"), systemImage: "arrow.left.and.right")
                            Spacer()
                            Slider(
                                value: Binding(
                                    get: { Double(appState.menubarTextMaxLength) },
                                    set: { appState.menubarTextMaxLength = Int($0) }
                                ),
                                in: 50...300,
                                step: 10,
                                onEditingChanged: { editing in
                                    isDraggingTextLength = editing
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                }
                            )
                            .frame(width: 150)
                            .controlSize(.small)
                            .onChange(of: appState.menubarTextMaxLength) { oldValue, newValue in
                                guard isDraggingTextLength else { return }
                                if newValue != oldValue {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                                }
                            }
                            
                            Text("\(appState.menubarTextMaxLength)pt")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }

                        HStack {
                            Label(L("settings.menubar.enableMarquee"), systemImage: "play.right.to.left")
                            Button(action: { showMarqueeInfo = true }) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .alert(L("settings.menubar.enableMarquee"), isPresented: $showMarqueeInfo) {
                                Button("OK", role: .cancel) {}
                            } message: {
                                Text(L("settings.menubar.enableMarquee.info"))
                            }
                            
                            Spacer()
                            Toggle("", isOn: $appState.enableMarquee)
                                .toggleStyle(.switch)
                        }

                        HStack {
                            Label(L("settings.menubar.showDeviceName"), systemImage: "iphone.gen3")
                            Spacer()
                            Toggle("", isOn: $appState.showMenubarDeviceName)
                                .toggleStyle(.switch)
                        }
                    }
                    .disabled(!appState.showMenubarText)
                    .opacity(appState.showMenubarText ? 1.0 : 0.6)

                    HStack {
                        Label(L("settings.menubar.batteryStyle"), systemImage: "battery.100")
                        Spacer()
                        Picker("", selection: $appState.menubarBatteryStyle) {
                            Text(L("settings.menubar.batteryStyle.both")).tag("both")
                            Text(L("settings.menubar.batteryStyle.icon")).tag("icon")
                            Text(L("settings.menubar.batteryStyle.percentage")).tag("percentage")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    HStack {
                        Label(L("settings.menubar.showPillStroke"), systemImage: "capsule")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarPillStroke)
                            .toggleStyle(.switch)
                    }

                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                VStack(spacing: 12) {

                    HStack {
                        Label(L("settings.menubar.showMusic"), systemImage: "music.note")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarMusicIcon)
                            .toggleStyle(.switch)
                    }

                    if appState.showMenubarMusicIcon {
                        HStack {
                            Label(L("settings.menubar.showAlbumArt"), systemImage: "photo")
                            Spacer()
                            ZStack {
                                Toggle("", isOn: $appState.showMenubarAlbumArt)
                                    .toggleStyle(.switch)
                                    .disabled(!appState.isPlus && appState.licenseCheck)

                                if !appState.isPlus && appState.licenseCheck {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            plusPopoverMessage = L("settings.menubar.albumArt.plusFeatureMessage")
                                            showingPlusPopover = true
                                        }
                                        .frame(width: 50, height: 30)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                VStack(spacing: 12) {

                    HStack {
                        Label(L("settings.menubar.notifications"), systemImage: "bell")
                        Spacer()
                        ZStack {
                            Picker("", selection: $appState.menubarNotificationStyle) {
                                Text(L("settings.menubar.notifications.both")).tag("both")
                                Text(L("settings.menubar.notifications.count")).tag("count")
                                Text(L("settings.menubar.notifications.icons")).tag("icons")
                                Text(L("settings.menubar.notifications.none")).tag("none")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .disabled(!appState.isPlus && appState.licenseCheck)

                            if !appState.isPlus && appState.licenseCheck {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        plusPopoverMessage = L("settings.menubar.notifications.plusFeatureMessage")
                                        showingPlusPopover = true
                                    }
                            }
                        }
                    }

                    if appState.menubarNotificationStyle == "count" || appState.menubarNotificationStyle == "both" {
                        HStack {
                            Label(L("settings.menubar.badgeStyle"), systemImage: "bell.badge")
                            Spacer()
                            Picker("", selection: $appState.menubarUnreadBadgeStyle) {
                                Text(L("settings.menubar.badgeStyle.badge")).tag("badge")
                                Text(L("settings.menubar.badgeStyle.text")).tag("text")
                                Text(L("settings.menubar.badgeStyle.none")).tag("none")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        if appState.menubarUnreadBadgeStyle == "badge" {
                            HStack {
                                Label(L("settings.menubar.badgeColor"), systemImage: "paintpalette")
                                Spacer()
                                Picker("", selection: $appState.menubarUnreadBadgeColor) {
                                    Text(L("settings.menubar.color.accent")).tag("accent")
                                    Text(L("settings.menubar.color.red")).tag("red")
                                    Text(L("settings.menubar.color.orange")).tag("orange")
                                    Text(L("settings.menubar.color.blue")).tag("blue")
                                    Text(L("settings.menubar.color.green")).tag("green")
                                    Text(L("settings.menubar.color.purple")).tag("purple")
                                    Text(L("settings.menubar.color.gray")).tag("gray")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    HStack {
                        Label(L("settings.menubar.notifications.calls"), systemImage: "phone")
                        Spacer()
                        ZStack {
                            Toggle("", isOn: $appState.showMenubarCallDetails)
                                .toggleStyle(.switch)
                                .disabled(!appState.isPlus && appState.licenseCheck)

                            if !appState.isPlus && appState.licenseCheck {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        plusPopoverMessage = L("settings.menubar.calls.plusFeatureMessage")
                                        showingPlusPopover = true
                                    }
                                    .frame(width: 50, height: 30)
                            }
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                PlusFeaturePopover(message: plusPopoverMessage)
                    .onTapGesture {
                        showingPlusPopover = false
                    }
            }
            .padding()
            .animation(.spring(), value: appState.showMenubarText)
            .animation(.spring(), value: appState.enableMarquee)
            .animation(.spring(), value: appState.showMenubarIcon)
            .animation(.spring(), value: appState.menubarBatteryStyle)
            .animation(.spring(), value: appState.showMenubarMusicIcon)
            .animation(.spring(), value: appState.showMenubarAlbumArt)
            .animation(.spring(), value: appState.showMenubarPillStroke)
            .animation(.spring(), value: appState.menubarNotificationStyle)
            .animation(.spring(), value: appState.menubarUnreadBadgeStyle)
            .animation(.spring(), value: appState.showMenubarCallDetails)
        }
    }

    private func L(_ key: String) -> String {
        return Localizer.shared.text(key)
    }
}
