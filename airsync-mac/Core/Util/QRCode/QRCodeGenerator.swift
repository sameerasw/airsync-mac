//
//  QRCodeGenerator.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-09-02.
//

import Foundation
import QRCode
internal import SwiftImageReadWrite
import CoreGraphics
import SwiftUI

class QRCodeGenerator {
    static func generateQRCode(for text: String, dimension: Int = 400) async -> CGImage? {
        do {
            // Use high error correction when embedding logos
            let doc = try QRCode.Document(
                utf8String: text,
                errorCorrection: .high
            )

            // Shapes
            doc.design.shape.eye = QRCode.EyeShape.RoundedPointingIn()
            doc.design.shape.onPixels = QRCode.PixelShape.Blob()
            doc.design.shape.pupil = QRCode.PupilShape.Seal()

            // Colors
            doc.design.backgroundColor(.clear)

            doc.design.style.eye = QRCode.FillStyle.Solid(.white)
            doc.design.style.pupil = QRCode.FillStyle.Solid(.white)
            doc.design.style.onPixels = QRCode.FillStyle.Solid(.white)

            // Export to CGImage
            let cgImage = try doc.cgImage(CGSize(width: dimension, height: dimension))
            return cgImage
        } catch {
            print("[qr-code-generator] QR generation failed: \(error)")
            return nil
        }
    }
}
