//
//  QuitHoldOverlayView.swift
//  AirSync
//

import SwiftUI
import Combine

class QuitHoldProgressModel: ObservableObject {
    @Published var isCancelled = false
}

struct QuitHoldOverlayView: View {
    let holdDuration: TimeInterval
    @ObservedObject var model: QuitHoldProgressModel
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 44, height: 44)

            Text("Hold ⌘Q to Quit")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(24)
        .applyGlassViewIfAvailable(cornerRadius: 18)
        .onAppear {
            withAnimation(.linear(duration: holdDuration)) {
                progress = 1
            }
        }
        .onChange(of: model.isCancelled) { _, isCancelled in
            guard isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                progress = 0
            }
        }
    }
}
