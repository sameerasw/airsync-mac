//
//  SideControlBar.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-03.
//

import SwiftUI

struct SideControlBar: View {
    @State private var hoveredPower = false
    @State private var hoveredVolUp = false
    @State private var hoveredVolDown = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Power Pill
            VStack {
                Button(action: {
                    triggerNavKey(26) // Power keycode
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                        .background(hoveredPower ? Color.white.opacity(0.15) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredPower = isHovered
                }
            }
            .frame(width: 40, height: 40)
            .glassBoxIfAvailable(radius: 20)
            
            // Volume Pill
            VStack(spacing: 8) {
                // Volume Up Button
                Button(action: {
                    triggerNavKey(24) // Volume Up keycode
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(hoveredVolUp ? Color.white.opacity(0.15) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredVolUp = isHovered
                }
                
                // Volume Down Button
                Button(action: {
                    triggerNavKey(25) // Volume Down keycode
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(hoveredVolDown ? Color.white.opacity(0.15) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredVolDown = isHovered
                }
            }
            .padding(.vertical, 6)
            .frame(width: 40, height: 80)
            .glassBoxIfAvailable(radius: 20)
        }
    }
    
    private func triggerNavKey(_ keycode: UInt32) {
        ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: keycode)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: keycode)
        }
    }
}
