import SwiftUI
internal import Combine

struct TrialActivationSheet: View {
    @ObservedObject var manager: TrialManager
    var onActivated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start AirSync+ Trial")
                .font(.headline)

            if let error = manager.lastError, !error.isEmpty {
                Text(":( \(error)")
                    .foregroundStyle(.red)
            }

            // Device ID display
            VStack(alignment: .leading, spacing: 6) {
                Text("Device ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Text(manager.deviceIdentifier)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manager.deviceIdentifier, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Device ID")
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Spacer()
                GlassButtonView(
                    label: "Cancel",
                    systemImage: "xmark.circle",
                    action: {
                        dismiss()
                    }
                )
                .keyboardShortcut(.cancelAction)

                GlassButtonView(
                    label: "Activate Trial",
                    systemImage: "checkmark.circle",
                    primary: true,
                    action: {
                        Task {
                            let activated = await manager.activateTrial()
                            if activated {
                                onActivated()
                                dismiss()
                            }
                        }
                    }
                )
                .disabled(manager.isPerformingRequest)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .overlay(alignment: .center) {
            if manager.isPerformingRequest {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .onAppear {
            manager.clearError()
        }
    }
}

#Preview {
    TrialActivationSheet(manager: TrialManager.shared)
}
