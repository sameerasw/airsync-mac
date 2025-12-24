//
//  FlowerShape.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-12-13.
//

import SwiftUI

struct FlowerShape: Shape {
    var petals: Int = 12          // petals count
    var amplitude: CGFloat = 0.05 // How wavy the edges are

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2 * (1 - amplitude)

        var path = Path()
        let steps = 720
        let step = 2 * .pi / CGFloat(steps)

        for i in 0...steps {
            let angle = CGFloat(i) * step
            let wave = sin(angle * CGFloat(petals))
            let radius = baseRadius * (1 + amplitude * wave)

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}

