import SwiftUI
import AppKit

/// Preferences UI for mirroring.
/// - Lets the user choose connection mode (ADB vs Remote Connect)
/// - Shows appropriate settings for the chosen mode
/// - For Remote Connect, exposes JSON-backed options that are sent to Android
struct MirrorSettingsView: View {
    var showModePicker: Bool = true

    // Connection mode
    @AppStorage("connection.mode") private var connectionMode: String = "remote" // "adb" or "remote"

    // Remote Connect JSON options (UserDefaults-backed)
    @AppStorage("mirror.transport") private var transport: String = "websocket"
    @AppStorage("mirror.fps") private var fps: Int = 30
    @AppStorage("mirror.quality") private var quality: Double = 0.6
    @AppStorage("mirror.maxWidth") private var maxWidth: Int = 1280
    @AppStorage("mirror.bitrateKbps") private var bitrateKbps: Int = 12000

    @AppStorage("mirror.stayOnTop") private var stayOnTop: Bool = false
    @AppStorage("mirror.stayAwake") private var stayAwake: Bool = false
    @AppStorage("mirror.blankDisplay") private var blankDisplay: Bool = false
    @AppStorage("mirror.noAudio") private var noAudio: Bool = false
    @AppStorage("mirror.continueApp") private var continueApp: Bool = false
    @AppStorage("mirror.directKeyboard") private var directKeyboard: Bool = false
    @AppStorage("mirror.sharedResolution") private var sharedResolution: Bool = false

    @AppStorage("mirror.launchX") private var launchX: Int = 0
    @AppStorage("mirror.launchY") private var launchY: Int = 0

    // Legacy/ADB compatibility (optional)
    @AppStorage("mirror.resolution") private var resolution: Int = 0

    @State private var copied = false

    var body: some View {
        if showModePicker {
            Form {
                Section("Mirror method") {
                    Picker("Method", selection: Binding(get: { connectionMode }, set: { connectionMode = $0 })) {
                        Text("Remote Connect").tag("remote")
                        Text("ADB Connect").tag("adb")
                    }
                    .pickerStyle(.segmented)
                    .help("Choose how you want to mirror: directly over WebSocket (Remote) or via ADB + scrcpy")
                }

                if connectionMode == "adb" {
                    adbSettingsInfo
                } else {
                    remoteJsonSettings
                }
            }
            .padding()
            .frame(minWidth: 460, minHeight: 420)
        } else {
            // Embedded mode: show only the Remote settings inline
            remoteInlineContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Inline-only variant without Form/Section wrappers for embedding in SettingsView
    private var remoteInlineContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mirroring Settings").font(.headline)

            // Transport
            HStack {
                Text("Transport")
                Spacer()
                Picker("Transport", selection: $transport) {
                    Text("WebSocket").tag("websocket")
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            // Bitrate
            HStack {
                Text("Video bitrate")
                Spacer()
                Slider(value: Binding(get: { Double(bitrateKbps) }, set: { bitrateKbps = Int($0.rounded()) }), in: 256...50000)
                    .frame(maxWidth: 300)
                Text("\(bitrateKbps / 1000) Mbps").monospacedDigit().foregroundStyle(.secondary)
            }

            // Max size
            HStack {
                Text("Max size")
                Spacer()
                Slider(value: Binding(get: { Double(maxWidth) }, set: { maxWidth = Int($0.rounded()) }), in: 320...4096)
                    .frame(maxWidth: 300)
                Text("\(maxWidth)").monospacedDigit().foregroundStyle(.secondary)
            }

            // FPS
            HStack {
                Text("FPS")
                Spacer()
                Stepper(value: $fps, in: 1...120) {
                    Text("\(fps)").monospacedDigit().foregroundStyle(.secondary)
                }
            }

            // Quality
            HStack {
                Text("Quality")
                Spacer()
                Slider(value: $quality, in: 0...1, step: 0.01)
                    .frame(maxWidth: 300)
                Text(String(format: "%.2f", quality)).monospacedDigit().foregroundStyle(.secondary)
            }

            // Toggles
            Toggle("Stay on top", isOn: $stayOnTop)
            Toggle("Stay awake (charging)", isOn: $stayAwake)
            Toggle("Blank display", isOn: $blankDisplay)
            Toggle("No audio", isOn: $noAudio)
            Toggle("Continue app after closing", isOn: $continueApp)
            Toggle("Direct keyboard input", isOn: $directKeyboard)
            Toggle("Apps & Desktop mode shared resolution", isOn: $sharedResolution)

            // Launch position
            HStack {
                Text("Launch position (x, y)")
                Spacer()
                Stepper(value: $launchX, in: -10000...10000) { Text("x: \(launchX)") }
                Stepper(value: $launchY, in: -10000...10000) { Text("y: \(launchY)") }
            }

            // Legacy resolution
            HStack {
                Text("Legacy resolution (longer edge)")
                Spacer()
                Stepper(value: $resolution, in: 0...8192) {
                    Text(resolution == 0 ? "(auto)" : "\(resolution)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }

            // JSON preview + copy
            HStack {
                Text("JSON preview (Remote Connect)").font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy JSON") {
                    #if os(macOS)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(previewJSON, forType: .string)
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                Text(previewJSON)
                    .textSelection(.enabled)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
        }
    }

    // MARK: - ADB Mode Placeholder / Guidance
    private var adbSettingsInfo: some View {
        Section("ADB Connect") {
            Text("ADB mirroring uses your existing scrcpy settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Start mirroring from the main screen. Advanced options (bitrate, max size, etc.) are applied via scrcpy and may be configured in your ADB section.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Remote Connect Options (JSON-backed)
    private var remoteJsonSettings: some View {
        Group {
            Section("Mirroring Settings") {
                HStack {
                    Text("Transport")
                    Spacer()
                    Picker("Transport", selection: $transport) {
                        Text("WebSocket").tag("websocket")
                    }
                    .frame(maxWidth: 200)
                    .labelsHidden()
                }

                HStack {
                    Text("Video bitrate")
                    Spacer()
                    Slider(value: Binding(get: { Double(bitrateKbps) }, set: { bitrateKbps = Int($0.rounded()) }), in: 256...50000)
                        .frame(maxWidth: 200)
                    Text("\(bitrateKbps / 1000) Mbps")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Max size")
                    Spacer()
                    Slider(value: Binding(get: { Double(maxWidth) }, set: { maxWidth = Int($0.rounded()) }), in: 320...4096)
                        .frame(maxWidth: 200)
                    Text("\(maxWidth)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("FPS")
                    Spacer()
                    Stepper(value: $fps, in: 1...120) {
                        Text("\(fps)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Quality")
                    Spacer()
                    Slider(value: $quality, in: 0...1, step: 0.01)
                        .frame(maxWidth: 200)
                    Text(String(format: "%.2f", quality))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Toggle("Stay on top", isOn: $stayOnTop)
                Toggle("Stay awake (charging)", isOn: $stayAwake)
                Toggle("Blank display", isOn: $blankDisplay)
                Toggle("No audio", isOn: $noAudio)
                Toggle("Continue app after closing", isOn: $continueApp)
                Toggle("Direct keyboard input", isOn: $directKeyboard)
                Toggle("Apps & Desktop mode shared resolution", isOn: $sharedResolution)

                HStack {
                    Text("Launch position (x, y)")
                    Spacer()
                    Stepper(value: $launchX, in: -10000...10000) { Text("x: \(launchX)") }
                    Stepper(value: $launchY, in: -10000...10000) { Text("y: \(launchY)") }
                }

                // Advanced/legacy (optional)
                HStack {
                    Text("Legacy resolution (longer edge)")
                    Spacer()
                    Stepper(value: $resolution, in: 0...8192) {
                        Text(resolution == 0 ? "(auto)" : "\(resolution)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("JSON preview (Remote Connect)") {
                VStack {
                    HStack {
                        Spacer()
                        Button(copied ? "Copied" : "Copy JSON") {
                            #if os(macOS)
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(previewJSON, forType: .string)
                            #endif
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ScrollView {
                        Text(previewJSON)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                }
            }
        }
    }

    // Build a JSON preview equivalent to what WebSocketServer will send
    private var previewJSON: String {
        var options: [String: Any] = [
            "transport": transport,
            "fps": fps,
            "quality": ((quality * 100).rounded() / 100),
            "maxWidth": maxWidth
        ]
        if bitrateKbps > 0 { options["bitrateKbps"] = bitrateKbps }
        if stayOnTop { options["stayOnTop"] = true }
        if stayAwake { options["stayAwake"] = true }
        if blankDisplay { options["blankDisplay"] = true }
        if noAudio { options["noAudio"] = true }
        if continueApp { options["continueApp"] = true }
        if directKeyboard { options["directKeyboard"] = true }
        if sharedResolution { options["sharedResolution"] = true }
        if launchX != 0 { options["launchX"] = launchX }
        if launchY != 0 { options["launchY"] = launchY }
        if resolution > 0 { options["resolution"] = resolution }

        let dict: [String: Any] = [
            "type": "mirrorRequest",
            "data": [
                "action": "start",
                "mode": "device",
                "options": options
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

#Preview {
    MirrorSettingsView()
}
