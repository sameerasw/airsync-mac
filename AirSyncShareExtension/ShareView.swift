import AppKit
import SwiftUI

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case working(String)
        case failed(String)
    }

    @Published var items: [SharePreviewItem] = []
    @Published var isLoadingPreview = true
    @Published var phase: Phase = .working("Preparing…")

    var listHeight: CGFloat {
        let rows = CGFloat(min(items.count, 3))
        return rows * 60 + max(rows - 1, 0) * 8
    }

    var totalHeight: CGFloat {
        let base: CGFloat = 215
        return items.isEmpty ? base : base + listHeight + 14
    }

    var summary: String {
        if isLoadingPreview { return "Checking items…" }
        guard !items.isEmpty else { return "Nothing to send" }
        let total = items.compactMap(\.byteCount).reduce(0, +)
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        return total > 0 ? "\(count) · \(SharePreviewLoader.format(total))" : count
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.items.isEmpty { itemList }
            status
            buttons
        }
        .padding(20)
        .frame(width: 380, height: model.totalHeight, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Send with AirSync")
                .font(.title3.weight(.semibold))
            Text(model.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.items) { item in
                    ShareItemRow(item: item)
                }
            }
        }
        .frame(height: model.listHeight)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(isFailed ? "Close" : "Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .modifier(GlassButtonStyle(prominent: false))
        }
        .controlSize(.large)
    }

    private var isFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }
}

private struct ShareItemRow: View {
    let item: SharePreviewItem

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(nsImage: item.icon).resizable().scaledToFit().padding(6)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .modifier(GlassCard())
    }
}

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct GlassButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
