//
//  RotatingAppIconView.swift
//  AirSync
//
//  Created by AI Assistant on 2024-03-13.
//

import SwiftUI
import AppKit

struct RotatingAppIconView: View {
    let size: CGFloat
    
    @State private var rotation: Double = 0
    
    init(size: CGFloat = 140) {
        self.size = size
    }
    
    private func loadSVG(named name: String) -> Image {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        // Fallback to asset catalog if bundle loading fails
        return Image(name)
    }
    
    var body: some View {
        ZStack {
            // Background logo that rotates
            loadSVG(named: "logo-bg")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
                .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotation)
            
            // Foreground logo that stays still
            loadSVG(named: "logo-fg")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .onAppear {
            rotation = 360
        }
    }
}

#Preview {
    RotatingAppIconView()
        .padding(50)
}
