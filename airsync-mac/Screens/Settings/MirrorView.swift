import SwiftUI

struct MirrorView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Mirror Preview")
                    .font(.title3).bold()
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

            H264DisplayView()
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(minWidth: 480, minHeight: 320)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 380)
    }
}

#Preview {
    MirrorView()
}
