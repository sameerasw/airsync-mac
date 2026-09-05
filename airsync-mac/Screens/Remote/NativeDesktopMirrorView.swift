//
//  NativeDesktopMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-04.
//

import SwiftUI

struct NativeDesktopMirrorView: View {
    var body: some View {
        ScrcpyBaseMirrorView(
            desktopMode: true,
            windowId: "nativeDesktopMirror",
            defaultTitle: "AirSync Desktop",
            defaultIconName: "desktopcomputer",
            defaultRatio: 16.0 / 9.0,
            isDesktopResizeEnabled: true
        )
    }
}
