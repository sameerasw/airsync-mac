//
//  DragAndDropExtensions.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-10-22.
//

import SwiftUI
import UniformTypeIdentifiers

// Custom UTType for AndroidApp
extension UTType {
    static let androidApp = UTType(exportedAs: "com.sameerasw.airsync.app")
}

// Extension to make AndroidApp draggable
extension View {
    func draggableApp(_ app: AndroidApp, preview: @escaping () -> some View) -> some View {
        self.onDrag {
            let provider = NSItemProvider()
            
            // Encode the app to JSON
            if let jsonData = try? JSONEncoder().encode(app) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.androidApp.identifier,
                    visibility: .all
                ) { completion in
                    completion(jsonData, nil)
                    return nil
                }
            }
            
            return provider
        }
    }
}
