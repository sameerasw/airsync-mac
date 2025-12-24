//
//  MenuBarNotificationsListView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-02.
//

import SwiftUI

struct MenuBarNotificationsListView: View {
    @ObservedObject private var appState = AppState.shared
    private let maxItems = 10

    var body: some View {
        Group {
            if !appState.notifications.isEmpty {
                List {
                    ForEach(appState.notifications.prefix(maxItems)) { notif in
                        NotificationCardView(
                            notification: notif,
                            deleteNotification: { appState.removeNotification(notif) },
                            hideNotification: { appState.hideNotification(notif) }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                        .applyGlassViewIfAvailable()
                        .animation(nil, value: appState.notifications.count)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 100, maxHeight: 750)
                .transaction { txn in txn.animation = nil }
            }
        }
    }
}

#Preview {
    MenuBarNotificationsListView()
}
