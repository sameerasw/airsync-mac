//
//  MediaPlayerView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//

import SwiftUI

struct MediaPlayerView: View {
    var music: DeviceStatus.Music
    @State private var showingPlusPopover = false

    var body: some View {
        ZStack{

            VStack{
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
                    font: .footnote,
                )



                Group {
                    if AppState.shared.isPlus {
                        HStack{
                                GlassButtonView(
                                    label: "",
                                    systemImage: "backward.end",
                                    iconOnly: true,
                                    size: .small,
                                    action: {
                                        WebSocketServer.shared.skipPrevious()
                                    }
                                )
                                .keyboardShortcut(
                                    .leftArrow,
                                    modifiers: .control
                                )
                                GlassButtonView(
                                    label: "",
                                    systemImage: music.isPlaying ? "pause.fill" : "play.fill",
                                    iconOnly: true,
                                    primary: true,
                                    action: {
                                        WebSocketServer.shared.togglePlayPause()
                                    }
                                )
                                .keyboardShortcut(
                                    .space,
                                    modifiers: .control
                                )

                                GlassButtonView(
                                    label: "",
                                    systemImage: "forward.end",
                                    iconOnly: true,
                                    size: .small,
                                    action: {
                                        WebSocketServer.shared.skipNext()
                                    }
                                )
                                .keyboardShortcut(
                                    .rightArrow,
                                    modifiers: .control
                                )
                        }
                    }
                }
            }
        }
        .padding()
        .applyGlassViewIfAvailable(cornerRadius: 20)
        .onTapGesture {
            showingPlusPopover = !AppState.shared.isPlus
        }
        .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
            PlusFeaturePopover(message: "Control media with AirSync+")
        }
    }
}


#Preview {
    MediaPlayerView(music: MockData.sampleMusic)
}
