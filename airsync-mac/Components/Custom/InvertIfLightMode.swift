//
//  InvertIfLightMode.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-10-07.
//

import SwiftUI


struct InvertIfLightMode: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .colorInvert()
                .saturation(0)
        } else {
            content
        }
    }
}
