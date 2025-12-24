//
//  SnowfallView.swift
//  airsync-mac
//
//  Created by Antigravity on 2025-12-24.
//

import SwiftUI

struct Snowflake: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var size: Double
    var speed: Double
    var opacity: Double
    var swing: Double
    var swingOffset: Double
}

struct SnowfallView: View {
    @State private var flakes: [Snowflake] = []
    private let flakeCount = 20
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                
                for flake in flakes {
                    let xOffset = sin(now * flake.swing + flake.swingOffset) * 10
                    let currentX = flake.x * size.width + xOffset
                    let currentY = (flake.y * size.height + now * flake.speed * 50).truncatingRemainder(dividingBy: size.height + 20) - 10
                    
                    let rect = CGRect(x: currentX, y: currentY, width: flake.size, height: flake.size)
                    context.opacity = flake.opacity
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
        .onAppear {
            generateFlakes()
        }
        .allowsHitTesting(false)
    }
    
    private func generateFlakes() {
        var newFlakes: [Snowflake] = []
        for _ in 0..<flakeCount {
            newFlakes.append(Snowflake(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 1...3),
                speed: Double.random(in: 0.5...1.5),
                opacity: Double.random(in: 0.2...0.6),
                swing: Double.random(in: 0.5...1.5),
                swingOffset: Double.random(in: 0...Double.pi * 2)
            ))
        }
        flakes = newFlakes
    }
}

#Preview {
    ZStack {
        Color.black
        SnowfallView()
    }
    .frame(width: 200, height: 400)
}
