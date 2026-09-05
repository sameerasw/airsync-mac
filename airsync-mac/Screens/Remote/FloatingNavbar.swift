//
//  FloatingNavbar.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-03.
//

import SwiftUI

struct FloatingNavbar: View {
    @State private var hoveredButton: Int? = nil // 0 for back, 1 for home, 2 for recents
    
    var body: some View {
        buttonsContent
            .frame(width: 140, height: 40)
            .glassBoxIfAvailable(radius: 20)
    }
    
    var buttonsContent: some View {
        HStack(spacing: 16) {
            // Back Button
            Button(action: {
                triggerNavKey(4)
            }) {
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(hoveredButton == 0 ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredButton = isHovered ? 0 : nil
            }
            
            // Home Button
            Button(action: {
                triggerNavKey(3)
            }) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(hoveredButton == 1 ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredButton = isHovered ? 1 : nil
            }
            
            // Recents Button
            Button(action: {
                triggerNavKey(187)
            }) {
                Image(systemName: "square.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(hoveredButton == 2 ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredButton = isHovered ? 2 : nil
            }
        }
    }
    
    private func triggerNavKey(_ keycode: UInt32) {
        // Send Key Down
        ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: keycode)
        // Send Key Up after short delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: keycode)
        }
    }
}
