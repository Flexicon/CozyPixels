import CoreGraphics
import Foundation
import UIKit

nonisolated struct PreviewRenderer: Sendable {
    var maximumPixelSize: Int

    init(maximumPixelSize: Int = 512) {
        self.maximumPixelSize = maximumPixelSize
    }

    func pngData(for document: PaintingDocument) -> Data? {
        guard document.width > 0, document.height > 0 else { return nil }

        let scale = max(1, min(12, maximumPixelSize / max(document.width, document.height)))
        let size = CGSize(width: document.width * scale, height: document.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)
        let colorsByID = Dictionary(uniqueKeysWithValues: document.palette.map { ($0.id, $0) })
        let wrongAttemptsByPixel = Dictionary(uniqueKeysWithValues: document.wrongAttempts.map { ($0.pixelIndex, $0) })

        return renderer.pngData { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for y in 0..<document.height {
                for x in 0..<document.width {
                    let pixelIndex = y * document.width + x
                    guard pixelIndex < document.targetColorIndexByPixel.count else { continue }

                    let targetColorID = Int(document.targetColorIndexByPixel[pixelIndex])
                    guard targetColorID > 0 else { continue }

                    let rect = CGRect(x: x * scale, y: y * scale, width: scale, height: scale)

                    if bitset.contains(pixelIndex), let color = colorsByID[targetColorID] {
                        color.uiColor().setFill()
                    } else if let wrongAttempt = wrongAttemptsByPixel[pixelIndex], let color = colorsByID[wrongAttempt.attemptedPaletteColorID] {
                        color.uiColor().withAlphaComponent(0.35).setFill()
                    } else {
                        UIColor(white: 0.82, alpha: 1).setFill()
                    }

                    context.fill(rect)
                }
            }
        }
    }
}

nonisolated private extension PaletteColor {
    func uiColor() -> UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
