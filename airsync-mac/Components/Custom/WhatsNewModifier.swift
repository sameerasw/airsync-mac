//
//  WhatsNewModifier.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-29.
//

import SwiftUI

struct WhatsNewModifier: ViewModifier {
    let item: WhatsNewTourItem
    let arrowEdge: Edge
    
    @ObservedObject var tourManager = WhatsNewTourManager.shared
    
    func body(content: Content) -> some View {
        content
            .popover(
                isPresented: Binding(
                    get: { tourManager.activeItem == item },
                    set: { isPresented in
                        if !isPresented {
                            tourManager.dismiss(item)
                        }
                    }
                ),
                arrowEdge: arrowEdge
            ) {
                WhatsNewTourPopover(item: item) {
                    tourManager.dismiss(item)
                }
            }
    }
}

extension View {
    func whatsNewPopover(item: WhatsNewTourItem, arrowEdge: Edge = .top) -> some View {
        self.modifier(WhatsNewModifier(item: item, arrowEdge: arrowEdge))
    }
}
