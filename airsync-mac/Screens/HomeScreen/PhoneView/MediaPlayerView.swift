//
//  MediaPlayerView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//

import SwiftUI
import Combine

// MARK: - Seekbar sub-view

private struct MediaSeekbarView: View {
    let music: DeviceStatus.Music
    @ObservedObject var appState = AppState.shared

    var body: some View {
        VStack(spacing: 2) {
            // Slider
            Slider(
                value: $appState.mediaPosition,
                in: 0...max(music.duration, 1),
                onEditingChanged: { editing in
                    appState.isDraggingMedia = editing
                    if !editing {
                        appState.handleMediaSeek(to: appState.mediaPosition)
                    }
                }
            )
            .accentColor(.primary)
            .padding(.horizontal, 2)

            // Time labels
            HStack {
                Text(formatTime(appState.mediaPosition))
                Spacer()
                Text(formatTime(music.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        let m = s / 60
        let h = m / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m % 60, s % 60)
        }
        return String(format: "%d:%02d", m, s % 60)
    }
}

// MARK: - Main MediaPlayerView

struct MediaPlayerView: View {
    var music: DeviceStatus.Music
    @State private var showingPlusPopover = false
    @AppStorage("syncAndroidPlaybackSeekbar") private var syncSeekbar: Bool = false

    private var hasSeekbar: Bool {
        music.duration > 0 && syncSeekbar
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                // Title + artist
                HStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                    EllipsesTextView(
                        text: music.title,
                        font: .caption
                    )
                }
                .frame(height: 14)

                EllipsesTextView(
                    text: music.artist,
                    font: .footnote
                )

                Group {
                    if AppState.shared.isPlus && AppState.shared.licenseCheck {
                        VStack(spacing: 6) {
                            // Seekbar (shown only when duration is known and toggle is enabled)
                            if hasSeekbar {
                                MediaSeekbarView(music: music)
                                    .padding(.top, 2)
                                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }

                            // Media control buttons
                            HStack {
                                if music.likeStatus == "liked" || music.likeStatus == "not_liked" {
                                    GlassButtonView(
                                        label: "",
                                        systemImage: {
                                            switch music.likeStatus {
                                            case "liked":     return "heart.fill"
                                            case "not_liked": return "heart"
                                            default:          return "heart.slash"
                                            }
                                        }(),
                                        iconOnly: true,
                                        action: {
                                            if music.likeStatus == "liked" {
                                                WebSocketServer.shared.unlike()
                                            } else if music.likeStatus == "not_liked" {
                                                WebSocketServer.shared.like()
                                            } else {
                                                WebSocketServer.shared.toggleLike()
                                            }
                                        }
                                    )
                                    .help("Like / Unlike")
                                } else {
                                    GlassButtonView(
                                        label: "",
                                        systemImage: "backward.end",
                                        iconOnly: true,
                                        action: { WebSocketServer.shared.skipPrevious() }
                                    )
                                    .keyboardShortcut(.leftArrow, modifiers: .control)
                                }

                                GlassButtonView(
                                    label: "",
                                    systemImage: music.isPlaying ? "pause.fill" : "play.fill",
                                    iconOnly: true,
                                    primary: true,
                                    action: { WebSocketServer.shared.togglePlayPause() }
                                )
                                .keyboardShortcut(.space, modifiers: .control)

                                GlassButtonView(
                                    label: "",
                                    systemImage: "forward.end",
                                    iconOnly: true,
                                    action: { WebSocketServer.shared.skipNext() }
                                )
                                .keyboardShortcut(.rightArrow, modifiers: .control)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .onTapGesture {
            showingPlusPopover = !AppState.shared.isPlus && AppState.shared.licenseCheck
        }
        .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
            PlusFeaturePopover(message: "Control media with AirSync+")
        }
    }
}

#Preview {
    MediaPlayerView(music: MockData.sampleMusic)
}
