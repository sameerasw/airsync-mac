//
//  NotificationView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI

struct NotificationCardView: View {

    let notification: Notification
    let deleteNotification: () -> Void
    let hideNotification: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top) {
                appIconView()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .padding(2)

                VStack(alignment: .leading) {
                    Text(notification.app + " - " + notification.title)
                        .font(.headline)

                    Text(notification.body)
                        .font(.body)

                    if let progressMax = notification.progressMax, progressMax > 0 {
                        let progress = notification.progress ?? 0
                        let isIndeterminate = notification.progressIndeterminate ?? false
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if !isIndeterminate {
                                HStack {
                                    ProgressView(value: Double(progress), total: Double(progressMax))
                                        .progressViewStyle(.linear)
                                        .tint(.accentColor)
                                    
                                    Text("\(Int(Double(progress) / Double(progressMax) * 100))%")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                    } else if notification.progressIndeterminate == true {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                    }

                    if !notification.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(notification.actions) { action in
                                if action.type == .reply {
                                    ReplyActionButton(notification: notification, action: action)
                                } else {
                                    GlassButtonView(
                                        label: action.name,
                                        action: {
                                            WebSocketServer.shared.sendNotificationAction(id: notification.nid, name: action.name)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hover Actions Pill
            if isHovering {
                HStack(spacing: 4) {
                    Button {
                        hideNotification()
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Hide")
                    .glassBoxIfAvailable(radius: 24)

                    Button {
                        deleteNotification()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .glassBoxIfAvailable(radius: 32)

                }
                .padding(6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .swipeActions(edge: .leading) {
            Button(role: .cancel) {
                hideNotification()
            } label: {
                Label(L("notifications.actions.hide"), systemImage: "xmark")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteNotification()
            } label: {
                Label(L("notifications.actions.dismiss"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                WebSocketServer.shared
                    .toggleNotification(
                        for: notification.package,
                        to: false
                    )
                hideNotification()
            } label: {
                Label(
                    "Mute app", systemImage: "bell.slash"
                )
            }

            Divider()

            Button {
                AppState.shared.configuringLaunchPreferenceFor = notification.package
            } label: {
                let configured = AppState.shared.notificationLaunchPreferences[notification.package] != nil
                Label(
                    configured ? "Edit notification click action" : "Set notification click action",
                    systemImage: "arrow.up.forward.app"
                )
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func appIconView() -> some View {
        if let path = AppState.shared.androidApps[notification.package]?.iconUrl,
           let image = Image(filePath: path) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 25, height: 25)
                .padding(5)
        } else {
            Image(systemName: "app.badge")
                .resizable()
        }
    }




}

private struct ReplyActionButton: View {
    @State private var showingField = false
    @State private var replyText = ""
    let notification: Notification
    let action: NotificationAction

    var body: some View {
        HStack(spacing: 4) {
            if showingField {
                TextField(action.name, text: $replyText, onCommit: send)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)


                GlassButtonView(
                    label: "Send",
                    systemImage: "paperplane",
                    iconOnly: true,
                    primary: true,
                    action: {
                        send()
                    }
                )
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            } else {

                GlassButtonView(
                    label: action.name,
                    systemImage: "arrowshape.turn.up.left",
                    iconOnly: true,
                    primary: true,
                    action: {
                        withAnimation { showingField = true }
                    }
                )
            }
        }
    }

    private func send() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        WebSocketServer.shared.sendNotificationAction(id: notification.nid, name: action.name, text: text)
        replyText = ""
        showingField = false
    }
}

#Preview {
    NotificationCardView(
        notification: MockData.sampleNotificaiton,
        deleteNotification: {},
        hideNotification: {}
    )
}
