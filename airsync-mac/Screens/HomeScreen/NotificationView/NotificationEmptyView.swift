//
//  NotificationEmptyView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-07.
//

import SwiftUI
import LottieUI
internal import Lottie

struct NotificationEmptyView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            LottieView("empty-notification-v1-clear")
                .loopMode(.loop)
                .frame(width: 100, height: 100)
                .modifier(InvertIfLightMode(colorScheme: colorScheme))

//            Text(L("notifications.empty.emoji"))
//                .font(.title)
//                .padding()


            Text(L("notifications.empty.title"))
                .padding()

        }
    }
}


#Preview {
    NotificationEmptyView()
}
