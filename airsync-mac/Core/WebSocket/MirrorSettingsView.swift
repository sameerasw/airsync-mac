import SwiftUI
import Foundation

struct MirrorSettingsView: View {
    @AppStorage("mirror.transport") private var transport: String = "UDP"
    @AppStorage("mirror.fps") private var fps: Int = 30
    @AppStorage("mirror.quality") private var quality: Double = 0.75
    @AppStorage("mirror.maxWidth") private var maxWidth: Int = 1080
    @AppStorage("mirror.bitrate") private var bitrate: Int?
    @AppStorage("mirror.resolution") private var resolution: Int?
    
    private let transports = ["UDP", "TCP", "HTTP"]
    private let fpsRange = 1...60
    private let qualityRange = 0.1...1.0
    private let maxWidthOptions = [480, 720, 1080, 1440, 2160]
    private let bitrateRange = 100_000...10_000_000
    private let resolutionOptions = [360, 480, 720, 1080, 1440, 2160]
    
    var body: some View {
        Form {
            Section(header: Text("Transport Protocol")) {
                Picker("Transport", selection: $transport) {
                    ForEach(transports, id: \.self) { proto in
                        Text(proto)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                Text("Select the network transport protocol used for mirroring.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Frame Rate")) {
                Stepper(value: $fps, in: fpsRange) {
                    Text("\(fps) FPS")
                }
                Text("Adjust the frame rate for the mirror stream.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Quality")) {
                Slider(value: $quality, in: qualityRange, step: 0.01)
                Text(String(format: "Quality: %.2f", quality))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Maximum Width")) {
                Picker("Max Width", selection: $maxWidth) {
                    ForEach(maxWidthOptions, id: \.self) { width in
                        Text("\(width) px")
                    }
                }
                Text("Limit the maximum width of the mirrored video.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Bitrate (optional)")) {
                Toggle(isOn: Binding(
                    get: { bitrate != nil },
                    set: { newVal in
                        if newVal {
                            bitrate = 1_000_000
                        } else {
                            bitrate = nil
                        }
                    })) {
                    Text("Enable Bitrate")
                }
                if bitrate != nil {
                    Stepper(value: Binding(
                        get: { bitrate ?? 1_000_000 },
                        set: { bitrate = $0 }
                    ), in: bitrateRange, step: 100_000) {
                        Text("\(bitrate ?? 0) bps")
                    }
                }
                Text("Set a target bitrate for the mirror stream. Leave disabled to use default.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Resolution (optional)")) {
                Toggle(isOn: Binding(
                    get: { resolution != nil },
                    set: { newVal in
                        if newVal {
                            resolution = 1080
                        } else {
                            resolution = nil
                        }
                    })) {
                    Text("Enable Resolution")
                }
                if resolution != nil {
                    Picker("Resolution", selection: Binding(
                        get: { resolution ?? 1080 },
                        set: { resolution = $0 }
                    )) {
                        ForEach(resolutionOptions, id: \.self) { res in
                            Text("\(res) p")
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                Text("Specify the resolution for the mirror stream. Leave disabled to use default.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 350)
    }
}

struct MirrorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MirrorSettingsView()
    }
}
