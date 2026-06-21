import CoreGraphics
import CoreText
import SwiftUI

struct PixelCanvasRenderState: Equatable {
    var document: PaintingDocument
    var cache: PixelCanvasRenderCache
    var pixelImage: CGImage?
    var selectedPaletteColorID: Int?
    var showGrid: Bool
    var showNumbers: Bool

    init(
        document: PaintingDocument,
        cache: PixelCanvasRenderCache? = nil,
        pixelImage: CGImage? = nil,
        selectedPaletteColorID: Int?,
        showGrid: Bool,
        showNumbers: Bool
    ) {
        self.document = document
        self.cache = cache ?? PixelCanvasRenderCache(document: document)
        self.pixelImage = pixelImage
        self.selectedPaletteColorID = selectedPaletteColorID
        self.showGrid = showGrid
        self.showNumbers = showNumbers
    }
}

struct PixelCanvasImageRenderer {
    func makeImage(document: PaintingDocument, cache: PixelCanvasRenderCache, selectedPaletteColorID: Int?) -> CGImage? {
        let width = document.width
        let height = document.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        for pixelIndex in document.targetColorIndexByPixel.indices {
            let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
            guard targetID > 0 else { continue }

            let byteIndex = pixelIndex * bytesPerPixel

            if cache.bitset.contains(pixelIndex), let targetColor = cache.paletteByID[targetID] {
                bytes[byteIndex] = targetColor.red
                bytes[byteIndex + 1] = targetColor.green
                bytes[byteIndex + 2] = targetColor.blue
                bytes[byteIndex + 3] = targetColor.alpha
                continue
            }

            let gray: UInt8 = selectedPaletteColorID == targetID ? 199 : 229
            bytes[byteIndex] = gray
            bytes[byteIndex + 1] = gray
            bytes[byteIndex + 2] = gray
            bytes[byteIndex + 3] = 255

            if let wrongAttempt = cache.wrongAttemptsByPixel[pixelIndex], let attemptedColor = cache.paletteByID[wrongAttempt.attemptedPaletteColorID] {
                blend(color: attemptedColor, alpha: 0.42, into: &bytes, at: byteIndex)
            }
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func blend(color: PaletteColor, alpha: Double, into bytes: inout [UInt8], at byteIndex: Int) {
        let sourceAlpha = min(max(Double(color.alpha) / 255 * alpha, 0), 1)
        let destinationAlpha = Double(bytes[byteIndex + 3]) / 255
        let outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha)
        guard outputAlpha > 0 else { return }

        bytes[byteIndex] = UInt8((Double(color.red) * sourceAlpha + Double(bytes[byteIndex]) * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        bytes[byteIndex + 1] = UInt8((Double(color.green) * sourceAlpha + Double(bytes[byteIndex + 1]) * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        bytes[byteIndex + 2] = UInt8((Double(color.blue) * sourceAlpha + Double(bytes[byteIndex + 2]) * destinationAlpha * (1 - sourceAlpha)) / outputAlpha)
        bytes[byteIndex + 3] = UInt8(outputAlpha * 255)
    }
}

struct PixelCanvasRenderCache: Equatable {
    var bitset: Bitset
    var paletteByID: [Int: PaletteColor]
    var wrongAttemptsByPixel: [Int: WrongAttempt]
    var isCompleted: Bool

    init(document: PaintingDocument) {
        let bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)

        self.bitset = bitset
        self.paletteByID = Dictionary(uniqueKeysWithValues: document.palette.map { ($0.id, $0) })
        self.wrongAttemptsByPixel = Dictionary(uniqueKeysWithValues: document.wrongAttempts.map { ($0.pixelIndex, $0) })
        self.isCompleted = Self.isDocumentCompleted(document, bitset: bitset)
    }

    private static func isDocumentCompleted(_ document: PaintingDocument, bitset: Bitset) -> Bool {
        for pixelIndex in document.targetColorIndexByPixel.indices where document.targetColorIndexByPixel[pixelIndex] > 0 {
            if !bitset.contains(pixelIndex) {
                return false
            }
        }

        return true
    }
}

struct PixelCanvasRenderer {
    private let state: PixelCanvasRenderState
    private let transform: CanvasTransform
    private let numberCellSizeThreshold: CGFloat = 18
    private let numberFontSize: CGFloat = 14

    init(state: PixelCanvasRenderState, transform: CanvasTransform = CanvasTransform()) {
        self.state = state
        self.transform = transform
    }

    func render(context: GraphicsContext, size: CGSize) {
        var context = context

        let document = state.document
        let imageSize = PixelSize(width: document.width, height: document.height)
        let geometry = transform.geometry(canvasSize: size, imageSize: imageSize)
        guard geometry.cellSize > 0 else { return }

        let bitset = state.cache.bitset
        let paletteByID = state.cache.paletteByID
        let wrongAttemptsByPixel = state.cache.wrongAttemptsByPixel
        let isCompleted = state.cache.isCompleted
        let viewport = CGRect(origin: .zero, size: size)
        let visibleRange = geometry.visiblePixelRange(in: viewport)

        guard let visibleRange else { return }

        if let pixelImage = state.pixelImage {
            drawPixelImage(context: &context, image: pixelImage, geometry: geometry)
        } else {
            drawPixels(context: &context, document: document, geometry: geometry, visibleRange: visibleRange, bitset: bitset, paletteByID: paletteByID, wrongAttemptsByPixel: wrongAttemptsByPixel)
        }

        if !isCompleted, state.showGrid, geometry.cellSize >= 3 {
            drawGrid(context: &context, geometry: geometry, visibleRange: visibleRange)
        }

        if !isCompleted, state.showNumbers, geometry.cellSize >= numberCellSizeThreshold {
            drawNumbers(context: &context, document: document, geometry: geometry, visibleRange: visibleRange, bitset: bitset, paletteByID: paletteByID)
        }
    }

    private func drawPixels(
        context: inout GraphicsContext,
        document: PaintingDocument,
        geometry: PixelGeometry,
        visibleRange: (x: Range<Int>, y: Range<Int>),
        bitset: Bitset,
        paletteByID: [Int: PaletteColor],
        wrongAttemptsByPixel: [Int: WrongAttempt]
    ) {
        let origin = geometry.origin
        let cellSize = geometry.cellSize

        for y in visibleRange.y {
            let rectY = origin.y + CGFloat(y) * cellSize

            for x in visibleRange.x {
                let pixelIndex = y * document.width + x
                guard pixelIndex < document.targetColorIndexByPixel.count else { continue }

                let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                guard targetID > 0, let targetColor = paletteByID[targetID] else { continue }

                let rect = CGRect(x: origin.x + CGFloat(x) * cellSize, y: rectY, width: cellSize, height: cellSize)
                let path = Path(rect)

                if bitset.contains(pixelIndex) {
                    context.fill(path, with: .color(targetColor.swiftUIColor))
                } else {
                    let base = state.selectedPaletteColorID == targetID ? Color(.systemGray3) : Color(.systemGray5)
                    context.fill(path, with: .color(base))

                    if let wrongAttempt = wrongAttemptsByPixel[pixelIndex], let attemptedColor = paletteByID[wrongAttempt.attemptedPaletteColorID] {
                        context.fill(path, with: .color(attemptedColor.swiftUIColor.opacity(0.42)))
                    }
                }
            }
        }
    }

    private func drawPixelImage(context: inout GraphicsContext, image: CGImage, geometry: PixelGeometry) {
        let destinationRect = CGRect(origin: geometry.origin, size: geometry.contentSize)

        context.withCGContext { cgContext in
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: destinationRect.minY + destinationRect.maxY)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.interpolationQuality = .none
            cgContext.setShouldAntialias(false)
            cgContext.draw(image, in: destinationRect)
            cgContext.restoreGState()
        }
    }

    private func drawGrid(context: inout GraphicsContext, geometry: PixelGeometry, visibleRange: (x: Range<Int>, y: Range<Int>)) {
        var path = Path()
        let origin = geometry.origin
        let minX = origin.x + CGFloat(visibleRange.x.lowerBound) * geometry.cellSize
        let maxX = origin.x + CGFloat(visibleRange.x.upperBound) * geometry.cellSize
        let minY = origin.y + CGFloat(visibleRange.y.lowerBound) * geometry.cellSize
        let maxY = origin.y + CGFloat(visibleRange.y.upperBound) * geometry.cellSize

        for x in visibleRange.x.lowerBound...visibleRange.x.upperBound {
            let position = origin.x + CGFloat(x) * geometry.cellSize
            path.move(to: CGPoint(x: position, y: minY))
            path.addLine(to: CGPoint(x: position, y: maxY))
        }

        for y in visibleRange.y.lowerBound...visibleRange.y.upperBound {
            let position = origin.y + CGFloat(y) * geometry.cellSize
            path.move(to: CGPoint(x: minX, y: position))
            path.addLine(to: CGPoint(x: maxX, y: position))
        }

        context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: max(0.5, 1 / max(geometry.scale, 1)))
    }

    private func drawNumbers(
        context: inout GraphicsContext,
        document: PaintingDocument,
        geometry: PixelGeometry,
        visibleRange: (x: Range<Int>, y: Range<Int>),
        bitset: Bitset,
        paletteByID: [Int: PaletteColor]
    ) {
        let origin = geometry.origin
        let cellSize = geometry.cellSize
        let numberLineByID = NumberLineCache.shared.lines(for: paletteByID.keys.sorted(), fontSize: numberFontSize)

        context.withCGContext { cgContext in
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: geometry.canvasSize.height)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.textMatrix = .identity

            for y in visibleRange.y {
                let centerY = origin.y + CGFloat(y) * cellSize + cellSize / 2

                for x in visibleRange.x {
                    let pixelIndex = y * document.width + x
                    guard pixelIndex < document.targetColorIndexByPixel.count, !bitset.contains(pixelIndex) else { continue }

                    let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                    guard targetID > 0, let numberLine = numberLineByID[targetID] else { continue }

                    let position = CGPoint(
                        x: origin.x + CGFloat(x) * cellSize + (cellSize - numberLine.bounds.width) / 2,
                        y: centerY - numberLine.bounds.height / 2
                    )
                    cgContext.textPosition = CGPoint(
                        x: position.x - numberLine.bounds.minX,
                        y: geometry.canvasSize.height - position.y - numberLine.bounds.height - numberLine.bounds.minY
                    )
                    CTLineDraw(numberLine.line, cgContext)
                }
            }

            cgContext.restoreGState()
        }
    }
}

final class NumberLineCache {
    static let shared = NumberLineCache()

    private struct Key: Hashable {
        var paletteIDs: [Int]
        var fontSize: CGFloat
    }

    private let textColor = CGColor(gray: 0, alpha: 0.72)
    private var cachedKey: Key?
    private var cachedLines: [Int: (line: CTLine, bounds: CGRect)] = [:]

    func lines(for paletteIDs: [Int], fontSize: CGFloat) -> [Int: (line: CTLine, bounds: CGRect)] {
        let key = Key(paletteIDs: paletteIDs, fontSize: fontSize)
        if cachedKey == key {
            return cachedLines
        }

        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let lines = Dictionary(uniqueKeysWithValues: paletteIDs.map { targetID in
            let text = NSAttributedString(
                string: "\(targetID)",
                attributes: [
                    .font: font,
                    .foregroundColor: textColor
                ]
            )
            let line = CTLineCreateWithAttributedString(text)
            let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
            return (targetID, (line: line, bounds: bounds))
        })

        cachedKey = key
        cachedLines = lines
        return lines
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
