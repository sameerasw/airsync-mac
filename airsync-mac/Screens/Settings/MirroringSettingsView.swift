//
//  MirroringSettingsView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-20.
//

import SwiftUI
import AppKit

struct MirroringSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("scrcpyOnTop") private var scrcpyOnTop = false
    @AppStorage("stayAwake") private var stayAwake = false
    @AppStorage("turnScreenOff") private var turnScreenOff = false
    @AppStorage("noAudio") private var noAudio = false
    @AppStorage("manualPosition") private var manualPosition = false
    @AppStorage("continueApp") private var continueApp = false
    @AppStorage("directKeyInput") private var directKeyInput = true
    @AppStorage("scrcpyDesktopDpi") private var scrcpyDesktopDpi = ""

    @State private var tempBitrate: Double = 4.00
    @State private var tempResolution: Double = 1200.00
    @State private var isDragging = false
    @State private var isDraggingBitrate = false
    @State private var isDraggingResolution = false
    @State private var xCoords: String = "0"
    @State private var yCoords: String = "0"

    @AppStorage("swapCmdAndCtrl") private var swapCmdAndCtrl = true
    @AppStorage("showMirrorControls") private var showMirrorControls = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if appState.isPlus {
                    unlockedMirroringViewContent
                } else {
                    androidMirroringSection
                    lockedMirroringViewContent
                }
            }
            .padding()
        }
        .onAppear {
            tempBitrate = Double(AppState.shared.scrcpyBitrate)
            tempResolution = Double(AppState.shared.scrcpyResolution)
            let coords = UserDefaults.standard.manualPositionCoords
            xCoords = coords.indices.contains(0) ? coords[0] : "0"
            yCoords = coords.indices.contains(1) ? coords[1] : "0"
        }
    }

    private var androidMirroringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection(title: L("settings.mirroring.androidMirroring"), icon: "keyboard")
            
            VStack(spacing: 12) {
                SettingsToggleView(
                    name: L("settings.mirroring.swapCmdCtrl"),
                    icon: "arrow.triangle.2.circlepath",
                    isOn: $swapCmdAndCtrl
                )
                
                SettingsToggleView(
                    name: L("settings.mirroring.showMirrorControls"),
                    icon: "sidebar.left",
                    isOn: $showMirrorControls
                )
            }
            .padding()
            .glassBoxIfAvailable(radius: 18)
        }
    }

    private var unlockedMirroringViewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 16) {
                HStack{
                    Label(L("settings.mirroring.defaultMode"), systemImage: "iphone")
                    Spacer()
                    Picker("", selection: $appState.useNativeMirroringByDefault) {
                        Text(L("settings.mirroring.scrcpy.title")).tag(false)
                        Text(L("settings.mirroring.native.title")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                }

                if(appState.useNativeMirroringByDefault) {
                    Text(L("settings.mirroring.native.info"))
                        .font(.caption)
                } else {
                    Text(L("settings.mirroring.scrcpy.info"))
                        .font(.caption)
                }
            }
            .padding()
            .glassBoxIfAvailable(radius: 18)

            VStack(spacing: 16) {
                HStack{
                    Label(L("settings.mirroring.desktop.defaultMode"), systemImage: "desktopcomputer")
                    Spacer()
                    Picker("", selection: $appState.useNativeDesktopMirroringByDefault) {
                        Text(L("settings.mirroring.scrcpy.title")).tag(false)
                        Text(L("settings.mirroring.native.title")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                }

                Text(appState.useNativeDesktopMirroringByDefault
                     ? "Uses the built-in stream for desktop mode — no scrcpy binary required."
                     : "Launches desktop mode via the scrcpy binary.")
                    .font(.caption)
            }
            .padding()
            .glassBoxIfAvailable(radius: 18)

            
            androidMirroringSection

            headerSection(title: L("settings.mirroring.appMirroring"), icon: "apps.iphone.badge.plus")

            VStack(spacing: 16) {
                HStack {
                    Label(L("settings.mirroring.enableAppMirroring"), systemImage: "apps.iphone.badge.plus")
                    Spacer()
                    Toggle("", isOn: $appState.mirroringPlus)
                        .toggleStyle(.switch)
                }

                Divider()

                VStack(spacing: 12) {
                    HStack {
                        Text(L("settings.mirroring.videoBitrate"))
                        Spacer()

                        Slider(
                            value: $tempBitrate,
                            in: 1...12,
                            step: 1,
                            onEditingChanged: { editing in
                                if !editing {
                                    AppState.shared.scrcpyBitrate = Int(tempBitrate)
                                }
                                if editing {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                } else {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                }
                                isDraggingBitrate = editing
                                isDragging = editing
                            }
                        )
                        .focusable(false)
                        .frame(maxWidth: 150)
                        .onChange(of: tempBitrate) { oldValue, newValue in
                            guard isDraggingBitrate else { return }
                            if newValue != oldValue {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                            }
                        }

                        Text(String(format: L("settings.mirroring.bitrateFormat"), AppState.shared.scrcpyBitrate))
                            .monospacedDigit()
                            .foregroundColor(isDragging ? .accentColor : .secondary)
                            .frame(width: 60, alignment: .leading)
                    }

                    HStack {
                        Text(L("settings.mirroring.maxSize"))
                        Spacer()

                        Slider(
                            value: $tempResolution,
                            in: 800...2600,
                            step: 200,
                            onEditingChanged: { editing in
                                if !editing {
                                    AppState.shared.scrcpyResolution = Int(tempResolution)
                                }
                                if editing {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                } else {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                }
                                isDraggingResolution = editing
                                isDragging = editing
                            }
                        )
                        .focusable(false)
                        .frame(maxWidth: 150)
                        .onChange(of: tempResolution) { oldValue, newValue in
                            guard isDraggingResolution else { return }
                            if newValue != oldValue {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                            }
                        }

                        Text("\(AppState.shared.scrcpyResolution)")
                            .monospacedDigit()
                            .foregroundColor(isDragging ? .accentColor : .secondary)
                            .frame(width: 60, alignment: .leading)
                    }

                    SettingsToggleView(name: L("settings.mirroring.stayOnTop"), icon: "inset.filled.toptrailing.rectangle.portrait", isOn: $scrcpyOnTop)

                    SettingsToggleView(name: L("settings.mirroring.stayAwake"), icon: "cup.and.heat.waves", isOn: $stayAwake)

                    SettingsToggleView(name: L("settings.mirroring.blankDisplay"), icon: "iphone.gen3.slash", isOn: $turnScreenOff)

                    SettingsToggleView(name: L("settings.mirroring.noAudio"), icon: "speaker.slash", isOn: $noAudio)

                    SettingsToggleView(name: L("settings.mirroring.continueApp"), icon: "arrow.turn.up.forward.iphone", isOn: $continueApp)

                    SettingsToggleView(name: L("settings.mirroring.directKeyboardInput"), icon: "keyboard.chevron.compact.down", isOn: $directKeyInput)

                    HStack {
                        Text(L("settings.mirroring.dpi"))
                        Spacer()
                        TextField(L("settings.mirroring.dpi"), text: Binding(
                            get: { UserDefaults.standard.scrcpyDesktopDpi },
                            set: { newValue in
                                UserDefaults.standard.scrcpyDesktopDpi = newValue.filter { "0123456789".contains($0) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 60)
                    }

                    HStack {
                        Text(L("settings.mirroring.manualPosition"))
                        Spacer()

                        TextField(L("settings.mirroring.x"), text: $xCoords)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: xCoords) { oldValue, newValue in
                                xCoords = newValue.filter { "0123456789".contains($0) }
                            }
                            .disabled(!manualPosition)

                        TextField(L("settings.mirroring.y"), text: $yCoords)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: yCoords) { oldValue, newValue in
                                yCoords = newValue.filter { "0123456789".contains($0) }
                            }
                            .disabled(!manualPosition)

                        GlassButtonView(
                            label: L("settings.mirroring.set"),
                            action: {
                                UserDefaults.standard.manualPositionCoords = [xCoords, yCoords]
                            }
                        )
                        .disabled(xCoords.isEmpty || yCoords.isEmpty || !manualPosition)

                        Toggle("", isOn: $manualPosition)
                            .toggleStyle(.switch)
                    }
                }
            }
            .padding()
            .glassBoxIfAvailable(radius: 18)
        }
    }

    private var lockedMirroringViewContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "apps.iphone.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 40)
                .padding(.bottom, 10)

            PlusFeaturePopover(message: L("settings.mirroring.plusFeatureMessage"))
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func headerSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

