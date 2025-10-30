import SwiftUI

struct MirrorView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Mirror Preview")
                    .font(.title2).bold()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(minWidth: 400, minHeight: 300)

                VStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Waiting for mirror frames…")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Text("This is a placeholder view. When frames arrive via WebSocketServer.handleMirrorFrame, wire decoding and rendering here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 380)
    }
}

#Preview {
    MirrorView()
}
