import SwiftUI

struct PixelCanvasRenderState: Equatable {
    var document: PaintingDocument
    var selectedPaletteColorID: Int?
    var showGrid: Bool
    var showNumbers: Bool
    var scale: CGFloat
}

struct PixelCanvasRenderer {
    private let state: PixelCanvasRenderState
    private let transform: CanvasTransform

    init(state: PixelCanvasRenderState, transform: CanvasTransform = CanvasTransform()) {
        self.state = state
        self.transform = transform
    }

    func render(context: GraphicsContext, size: CGSize) {
        var context = context
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.systemBackground)))

        let document = state.document
        let imageSize = PixelSize(width: document.width, height: document.height)
        let geometry = transform.geometry(canvasSize: size, imageSize: imageSize)
        guard geometry.cellSize > 0 else { return }

        let bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)
        let paletteByID = Dictionary(uniqueKeysWithValues: document.palette.map { ($0.id, $0) })
        let wrongAttemptsByPixel = Dictionary(uniqueKeysWithValues: document.wrongAttempts.map { ($0.pixelIndex, $0) })
        let viewport = CGRect(origin: .zero, size: size)
        let visibleRange = geometry.visiblePixelRange(in: viewport)

        drawCheckerboard(context: &context, geometry: geometry)
        guard let visibleRange else { return }

        drawPixels(context: &context, document: document, geometry: geometry, visibleRange: visibleRange, bitset: bitset, paletteByID: paletteByID, wrongAttemptsByPixel: wrongAttemptsByPixel)

        if state.showGrid, geometry.cellSize >= 3 {
            drawGrid(context: &context, geometry: geometry, visibleRange: visibleRange)
        }

        if state.showNumbers, geometry.cellSize >= 18 {
            drawNumbers(context: &context, document: document, geometry: geometry, visibleRange: visibleRange, bitset: bitset, paletteByID: paletteByID)
        }
    }

    private func drawCheckerboard(context: inout GraphicsContext, geometry: PixelGeometry) {
        let contentRect = CGRect(origin: geometry.origin, size: geometry.contentSize)
        context.fill(Path(contentRect), with: .color(Color(.secondarySystemBackground)))

        guard geometry.cellSize >= 6 else { return }
        guard let visibleRange = geometry.visiblePixelRange(in: CGRect(origin: .zero, size: geometry.canvasSize)) else { return }

        for y in visibleRange.y {
            for x in visibleRange.x where (x + y).isMultiple(of: 2) {
                context.fill(Path(geometry.rect(for: PixelCoordinate(x: x, y: y))), with: .color(Color(.tertiarySystemBackground)))
            }
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
            let rectY = origin.y + CGFloat(y) * cellSize + 0.25

            for x in visibleRange.x {
                let pixelIndex = y * document.width + x
                guard pixelIndex < document.targetColorIndexByPixel.count else { continue }

                let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                guard targetID > 0, let targetColor = paletteByID[targetID] else { continue }

                let rect = CGRect(x: origin.x + CGFloat(x) * cellSize + 0.25, y: rectY, width: cellSize - 0.5, height: cellSize - 0.5)
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
        let fontSize = min(geometry.cellSize * 0.42, 18)
        let origin = geometry.origin
        let cellSize = geometry.cellSize

        for y in visibleRange.y {
            let centerY = origin.y + CGFloat(y) * cellSize + cellSize / 2

            for x in visibleRange.x {
                let pixelIndex = y * document.width + x
                guard pixelIndex < document.targetColorIndexByPixel.count, !bitset.contains(pixelIndex) else { continue }

                let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                guard targetID > 0, paletteByID[targetID] != nil else { continue }

                let text = Text("\(targetID)").font(.system(size: fontSize, weight: .semibold, design: .rounded)).foregroundStyle(.black.opacity(0.72))
                context.draw(text, at: CGPoint(x: origin.x + CGFloat(x) * cellSize + cellSize / 2, y: centerY), anchor: .center)
            }
        }
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
