//
//  PhoneView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI

struct PhoneView: View {
    @ObservedObject var appState = AppState.shared
    @State private var displayedImage: NSImage?
    // 3D tilt state
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var isInteracting: Bool = false

    var body: some View {
        GeometryReader { geo in
            let cardWidth: CGFloat = 220
            let cardHeight: CGFloat = 460
            let corner: CGFloat = 24
            ZStack {
                // Wallpaper background layer(s) WITH 3D tilt
                FadingImageView(image: displayedImage, duration: 0.75)
                    .overlay(
                        LinearGradient(
                            colors: [Color.black.opacity(0.35), Color.black.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                .scaleEffect(isInteracting ? 1.085 : 1.035)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0))
                .animation(.easeOut(duration: 0.22), value: tiltX)
                .animation(.easeOut(duration: 0.22), value: tiltY)
                .animation(.easeOut(duration: 0.25), value: isInteracting)


                // Seasonal Snowfall Overlay
                SnowfallView()

                // Foreground content
                ScreenView()
                    .padding(.horizontal, 4)
                    .transition(.blurReplace)
                
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 22, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: corner))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let size = CGSize(width: cardWidth, height: cardHeight)
                        let origin = CGPoint(
                            x: value.location.x - (geo.size.width - cardWidth) / 2,
                            y: value.location.y - (geo.size.height - cardHeight) / 2
                        )
                        let dx = origin.x - size.width / 2
                        let dy = origin.y - size.height / 2
                        let maxAngle: CGFloat = 5 // tight limit to prevent edge exposure
                        if !isInteracting { isInteracting = true }
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.2)) {
                            let rawY = Double((dx / size.width) * maxAngle)
                            let rawX = Double((-dy / size.height) * maxAngle)
                            let limit = Double(maxAngle)
                            tiltY = max(min(rawY, limit), -limit)
                            tiltX = max(min(rawX, limit), -limit)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            tiltX = 0
                            tiltY = 0
                            isInteracting = false
                        }
                    }
            )
            .onAppear { updateImage() }
            .onChange(of: appState.status?.music.isPlaying) { updateImage() }
            .onChange(of: appState.status?.music.albumArt) { updateImage() }
            .onChange(of: AppState.shared.currentDeviceWallpaperBase64) { updateImage() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateImage() {
        let base64 = (appState.status?.music.isPlaying ?? false)
            ? appState.status?.music.albumArt
            : AppState.shared.currentDeviceWallpaperBase64

        guard let base64 = base64,
              let data = Data(base64Encoded: base64.stripBase64Prefix()),
              let nsImage = NSImage(data: data) else { return }
        // Setting displayedImage triggers fade in representable
        displayedImage = nsImage
    }
}

#Preview {
    PhoneView()
}
