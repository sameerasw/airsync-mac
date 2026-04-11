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

    @State private var displayedPosition: Double = 0
    @State private var isDragging = false
    /// When the user last performed a seek (to enforce a blackout window)
    @State private var lastSeekTime: Date = .distantPast
    /// The position the user seeked to, used for delta-based stale-packet rejection
    @State private var seekTargetPosition: Double = -1

    // A single declarative timer that ticks every second.
    // We simply ignore ticks when paused or dragging.
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 2) {
            // Slider
            Slider(
                value: $displayedPosition,
                in: 0...max(music.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        seekTargetPosition = displayedPosition
                        lastSeekTime = Date()
                        WebSocketServer.shared.seekTo(positionSeconds: displayedPosition)
                    }
                }
            )
            .accentColor(.primary)
            .padding(.horizontal, 2)

            // Time labels
            HStack {
                Text(formatTime(displayedPosition))
                Spacer()
                Text(formatTime(music.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .onAppear { syncFromStatus() }
        .onChange(of: music.position) { _ in
            guard !isDragging else { return }
            let incoming = music.position >= 0 ? music.position : 0
            let sinceSeeked = Date().timeIntervalSince(lastSeekTime)

            // Seek-target confirmation guard (replaces the old 5-second blanket blackout):
            // After a Mac-initiated seek, we know the target position. Instead of blocking
            // everything for N seconds, we selectively accept packets that land near our target
            // and reject packets that are still at the old pre-seek position.
            //
            //  - seekTargetPosition >= 0 means we have a pending unconfirmed Mac seek.
            //  - Accept: incoming is within 10s of the target → fresh post-seek packet. Confirmed!
            //  - Reject: incoming is far behind the target → stale pre-seek packet. Drop it.
            //  - Expire: if 10 seconds pass without confirmation, clear the guard and resume normally.
            if seekTargetPosition >= 0 && sinceSeeked < 10.0 {
                // A packet is a "fresh confirmation" only if its position is within 10 seconds
                // of the seek target in EITHER direction (handles both forward and backward seeks).
                //
                // Forward seek (3:00→6:00):  stale=3:05 → |3:05-6:00|=175s → reject ✅
                //                            fresh=6:01 → |6:01-6:00|=1s   → accept ✅
                //
                // Backward seek (6:00→3:00): stale=6:05 → |6:05-3:00|=185s → reject ✅
                //                            fresh=3:01 → |3:01-3:00|=1s   → accept ✅
                if abs(incoming - seekTargetPosition) <= 10.0 {
                    seekTargetPosition = -1
                    syncFromStatus()
                }
                // else: stale packet (far from seek target), drop silently.
                return
            }
            // If we get here, either no pending seek or the 10s guard expired.
            // Clear any stale seekTargetPosition.
            if seekTargetPosition >= 0 { seekTargetPosition = -1 }

            // Residual delta guard (8s window): catches very delayed stale packets that
            // somehow slipped past the seek-target guard after it expired.
            if sinceSeeked < 8.0 && incoming < displayedPosition - 5.0 { return }

            syncFromStatus()
        }
        .onReceive(timer) { _ in
            // Declarative tick: advance only when playing, not buffering, and not dragging
            guard music.isPlaying, !music.isBuffering, !isDragging else { return }
            let next = displayedPosition + 1.0
            displayedPosition = music.duration > 0 ? min(next, music.duration) : next
        }
        .onChange(of: music.title) { _ in
            // Track changed — immediately clear the seek guard and adopt the new position.
            // Without this, the seek-target filter would reject the new song's 0:00 start
            // as a "stale packet" for up to 10 seconds if a seek was recent.
            seekTargetPosition = -1
            lastSeekTime = .distantPast
            syncFromStatus()
        }
    }

    // MARK: - Helpers

    private func syncFromStatus() {
        guard music.position >= 0 else { return }
        let incoming = music.position
        let delta = incoming - displayedPosition   // positive = Android ahead, negative = Android behind

        // Asymmetric dead zone:
        //
        // • Android ahead of Mac by > 3s  → we drifted behind → snap forward.
        //   This is uncommon (Mac's local timer usually runs slightly ahead).
        //
        // • Android behind Mac by > 10s  → genuine desync (Android was buffering/paused and
        //   we didn't catch it) → snap backward to re-sync.
        //
        // • |delta| <= threshold → ignore. The Mac's local timer is already close.
        //   In particular, this swallows the "7:50 arrives while Mac is at 7:55" case
        //   (Mac ran 5s ahead of the stale packet → within the 10s backward tolerance → no snap).
        if delta > 3.0 || delta < -10.0 {
            displayedPosition = incoming
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
                                            } else {
                                                WebSocketServer.shared.like()
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
