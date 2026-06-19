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

        drawCheckerboard(context: &context, geometry: geometry)
        drawPixels(context: &context, document: document, geometry: geometry, bitset: bitset, paletteByID: paletteByID, wrongAttemptsByPixel: wrongAttemptsByPixel)

        if state.showGrid, geometry.cellSize >= 3 {
            drawGrid(context: &context, geometry: geometry)
        }

        if state.showNumbers, geometry.cellSize >= 18 {
            drawNumbers(context: &context, document: document, geometry: geometry, bitset: bitset, paletteByID: paletteByID)
        }
    }

    private func drawCheckerboard(context: inout GraphicsContext, geometry: PixelGeometry) {
        let contentRect = CGRect(origin: geometry.origin, size: geometry.contentSize)
        context.fill(Path(contentRect), with: .color(Color(.secondarySystemBackground)))

        guard geometry.cellSize >= 6 else { return }

        for y in 0..<geometry.imageSize.height {
            for x in 0..<geometry.imageSize.width where (x + y).isMultiple(of: 2) {
                context.fill(Path(geometry.rect(for: PixelCoordinate(x: x, y: y))), with: .color(Color(.tertiarySystemBackground)))
            }
        }
    }

    private func drawPixels(
        context: inout GraphicsContext,
        document: PaintingDocument,
        geometry: PixelGeometry,
        bitset: Bitset,
        paletteByID: [Int: PaletteColor],
        wrongAttemptsByPixel: [Int: WrongAttempt]
    ) {
        for y in 0..<document.height {
            for x in 0..<document.width {
                let pixelIndex = y * document.width + x
                guard pixelIndex < document.targetColorIndexByPixel.count else { continue }

                let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                guard targetID > 0, let targetColor = paletteByID[targetID] else { continue }

                let rect = geometry.rect(for: PixelCoordinate(x: x, y: y)).insetBy(dx: 0.25, dy: 0.25)
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

    private func drawGrid(context: inout GraphicsContext, geometry: PixelGeometry) {
        var path = Path()
        let origin = geometry.origin
        let width = geometry.contentSize.width
        let height = geometry.contentSize.height

        for x in 0...geometry.imageSize.width {
            let position = origin.x + CGFloat(x) * geometry.cellSize
            path.move(to: CGPoint(x: position, y: origin.y))
            path.addLine(to: CGPoint(x: position, y: origin.y + height))
        }

        for y in 0...geometry.imageSize.height {
            let position = origin.y + CGFloat(y) * geometry.cellSize
            path.move(to: CGPoint(x: origin.x, y: position))
            path.addLine(to: CGPoint(x: origin.x + width, y: position))
        }

        context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: max(0.5, 1 / max(geometry.scale, 1)))
    }

    private func drawNumbers(
        context: inout GraphicsContext,
        document: PaintingDocument,
        geometry: PixelGeometry,
        bitset: Bitset,
        paletteByID: [Int: PaletteColor]
    ) {
        let fontSize = min(geometry.cellSize * 0.42, 18)

        for y in 0..<document.height {
            for x in 0..<document.width {
                let pixelIndex = y * document.width + x
                guard pixelIndex < document.targetColorIndexByPixel.count, !bitset.contains(pixelIndex) else { continue }

                let targetID = Int(document.targetColorIndexByPixel[pixelIndex])
                guard targetID > 0, paletteByID[targetID] != nil else { continue }

                let rect = geometry.rect(for: PixelCoordinate(x: x, y: y))
                let text = Text("\(targetID)").font(.system(size: fontSize, weight: .semibold, design: .rounded)).foregroundStyle(.black.opacity(0.72))
                context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
