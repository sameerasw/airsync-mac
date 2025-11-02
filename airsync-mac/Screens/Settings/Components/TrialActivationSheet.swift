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
