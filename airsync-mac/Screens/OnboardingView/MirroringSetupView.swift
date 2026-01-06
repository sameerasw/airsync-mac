//
//  MirroringSetupView.swift
//  AirSync
//
//  Created by AI Assistant on 2025-09-04.
//

import SwiftUI
import AppKit

struct MirroringSetupView: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var adbAvailable = false
    @State private var scrcpyAvailable = false
    @State private var mediaControlAvailable = false
    @State private var checking = true
    @State private var brewAvailable = false
    @State private var installingPackage: String? = nil
    @State private var installLog: String = ""

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Optional Setup - Android Mirror and Media Playback")
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .padding()

                    Text("AirSync can mirror your Android screen to your Mac using ADB and scrcpy. This allows you to control your Android device from your Mac. But mirroring is an optional AirSync+ feature which you may or may not need. ADB and scrcpy are required for mirroring. For rich media features (showing the current song and controlling playback), we recommend installing the optional media-control CLI as well.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 500)


                    Text("media-control is optional, but enables Now Playing sync to Android and media keys from Mac. Recommended.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 500)

                    if checking {
                        ProgressView("Checking for ADB, scrcpy, and media-control...")
                            .frame(width: 200, height: 50)
                    } else {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: adbAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(adbAvailable ? .green : .red)
                                Text("ADB \(adbAvailable ? "found" : "not found")")
                            }

                            HStack {
                                Image(systemName: scrcpyAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(scrcpyAvailable ? .green : .red)
                                Text("scrcpy \(scrcpyAvailable ? "found" : "not found")")
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: mediaControlAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(mediaControlAvailable ? .green : .red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("media-control \(mediaControlAvailable ? "found" : "not found")")
                                }
                            }

                            if !adbAvailable || !scrcpyAvailable || !mediaControlAvailable {
                                // If ALL three missing and brew is not available, guide to Homebrew website.
                                if !brewAvailable && !adbAvailable && !scrcpyAvailable && !mediaControlAvailable {
                                    VStack(spacing: 12) {
                                        Text("Homebrew not found")
                                            .font(.headline)
                                        Text("To install ADB, scrcpy, and media-control, you need Homebrew. Click below to open brew.sh and follow the instructions. Then return here and tap 'Check Again'.")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: 520)

                                        GlassButtonView(
                                            label: "Get Homebrew",
                                            systemImage: "safari",
                                            size: .large,
                                            primary: true,
                                            action: {
                                                if let url = URL(string: "https://brew.sh") {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            }
                                        )

                                        GlassButtonView(
                                            label: "Check Again",
                                            systemImage: "arrow.clockwise",
                                            size: .large,
                                            action: {
                                                checking = true
                                                checkDependencies()
                                            }
                                        )
                                    }
                                    .transition(.identity)
                                } else {
                                    Text("Install with Homebrew or copy these commands:")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .frame(maxWidth: 500)

                                    VStack(alignment: .leading, spacing: 10) {
                                        if !adbAvailable {
                                            installRow(
                                                title: "android-platform-tools",
                                                command: "brew install android-platform-tools"
                                            )
                                        }
                                        if !scrcpyAvailable {
                                            installRow(
                                                title: "scrcpy",
                                                command: "brew install scrcpy"
                                            )
                                        }
                                        if !mediaControlAvailable {
                                            installRow(
                                                title: "media-control",
                                                command: "brew install media-control"
                                            )
                                        }
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(10)

                                    if let pkg = installingPackage {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 8) {
                                                ProgressView()
                                                Text("Installing \(pkg) via Homebrew…")
                                            }
                                            .font(.callout)
                                            .foregroundStyle(.secondary)

                                            ScrollView {
                                                Text(installLog.isEmpty ? "Running brew install…" : installLog)
                                                    .font(.system(.footnote, design: .monospaced))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            }
                                            .frame(maxHeight: 140)
                                            .background(Color.black.opacity(0.05))
                                            .cornerRadius(8)
                                        }
                                        .transition(.identity)
                                    }

                                    GlassButtonView(
                                        label: "Check Again",
                                        systemImage: "arrow.clockwise",
                                        size: .large,
                                        action: {
                                            checking = true
                                            checkDependencies()
                                        }
                                    )
                                    .disabled(installingPackage != nil)
                                    .transition(.identity)
                                }
                            } else {
                                Text("Great! ADB, scrcpy, and media-control are available.")
                                    .font(.callout)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }

            HStack(spacing: 16) {
                if adbAvailable && scrcpyAvailable {
                    GlassButtonView(
                        label: "Continue",
                        systemImage: "arrow.right.circle",
                        size: .large,
                        primary: true,
                        action: onNext
                    )
                    .transition(.identity)
                } else {
                    GlassButtonView(
                        label: "Skip",
                        size: .large,
                        action: onSkip
                    )
                    .transition(.identity)
                }
            }
            .padding(.bottom, 10)
        }
        .onAppear {
            checkDependencies()
        }
    }

    private func checkDependencies() {
        DispatchQueue.global(qos: .background).async {
            let adbFound = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) != nil
            let scrcpyFound = ADBConnector.findExecutable(named: "scrcpy", fallbackPaths: ADBConnector.possibleScrcpyPaths) != nil
            let mediaFound = ADBConnector.findExecutable(named: "media-control", fallbackPaths: ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]) != nil
            let brewFound = ADBConnector.findExecutable(named: "brew", fallbackPaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) != nil

            // let scrcpyFound = false

            DispatchQueue.main.async {
                self.adbAvailable = adbFound
                self.scrcpyAvailable = scrcpyFound
                self.mediaControlAvailable = mediaFound
                self.brewAvailable = brewFound
                self.checking = false
            }
        }
    }

    @ViewBuilder
    private func installRow(title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                Spacer()
                if brewAvailable {
                    GlassButtonView(
                        label: "Install",
                        systemImage: "square.and.arrow.down",
                        action: {
                            runBrewInstall(for: title)
                        }
                    )
                    .disabled(installingPackage != nil)
                }
                Button(action: {
                    copyToClipboard(command)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
            Spacer()
            Button(action: {
                copyToClipboard(command)
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func runBrewInstall(for formula: String) {
        guard installingPackage == nil else { return }
        installingPackage = formula
        installLog = ""

        DispatchQueue.global(qos: .userInitiated).async {
            // Find brew
            guard let brewPath = ADBConnector.findExecutable(named: "brew", fallbackPaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
                DispatchQueue.main.async {
                    self.brewAvailable = false
                    self.installingPackage = nil
                }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", formula]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Stream logs to UI
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
                DispatchQueue.main.async {
                    self.installLog += chunk
                }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    self.installingPackage = nil
                    self.checking = true
                }
                // Re-check tools after install
                self.checkDependencies()
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self.installLog += "\nFailed to run brew install: \(error.localizedDescription)"
                    self.installingPackage = nil
                }
            }
        }
    }
}

#Preview {
    MirroringSetupView(onNext: {}, onSkip: {})
}
