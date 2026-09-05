//
//  ScrcpyMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import SwiftUI

struct ScrcpyMirrorView: View {
    var body: some View {
        ScrcpyBaseMirrorView(
            desktopMode: false,
            windowId: "nativeMirror",
            defaultTitle: "AirSync Mirror",
            defaultIconName: "iphone",
            defaultRatio: 9.0 / 19.5,
            isDesktopResizeEnabled: false
        )
    }
}
