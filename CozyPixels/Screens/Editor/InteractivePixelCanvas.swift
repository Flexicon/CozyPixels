import SwiftUI

struct InteractivePixelCanvas: View {
    let document: PaintingDocument
    let selectedPaletteColorID: Int?
    let showGrid: Bool
    let showNumbers: Bool
    var resetToken: Int
    var minScale: CGFloat = 0.5
    var maxScale: CGFloat = 24
    var onTapPixel: (Int) -> Void
    var onStrokePixel: (Int, CanvasInputPhase) -> Void

    @State private var transform = CanvasTransform()
    @State private var gestureStartTransform = CanvasTransform()
    @State private var pinchStartLocation: CGPoint?
    @State private var lastStrokePixelIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PixelCanvasView(
                    state: PixelCanvasRenderState(
                        document: document,
                        selectedPaletteColorID: selectedPaletteColorID,
                        showGrid: showGrid,
                        showNumbers: showNumbers
                    ),
                    transform: transform
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                CanvasInputOverlay(
                    onTap: { point in
                        if let pixelIndex = pixelIndex(at: point, canvasSize: proxy.size) {
                            onTapPixel(pixelIndex)
                        }
                    },
                    onPan: { translation, phase in
                        handlePan(translation: translation, phase: phase)
                    },
                    onPinch: { magnification, location, phase in
                        handlePinch(magnification: magnification, location: location, phase: phase, canvasSize: proxy.size)
                    },
                    onPaintStroke: { point, phase in
                        handlePaintStroke(at: point, phase: phase, canvasSize: proxy.size)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onChange(of: resetToken) { _, _ in
                resetTransform()
            }
        }
    }

    private func handlePan(translation: CGSize, phase: CanvasInputPhase) {
        switch phase {
        case .began:
            gestureStartTransform = transform
        case .changed:
            transform.offset = CGSize(
                width: gestureStartTransform.offset.width + translation.width,
                height: gestureStartTransform.offset.height + translation.height
            )
        case .ended, .cancelled:
            gestureStartTransform = transform
        }
    }

    private func handlePinch(magnification: CGFloat, location: CGPoint, phase: CanvasInputPhase, canvasSize: CGSize) {
        let imageSize = PixelSize(width: document.width, height: document.height)

        switch phase {
        case .began:
            gestureStartTransform = transform
            pinchStartLocation = location
        case .changed:
            let anchorLocation = pinchStartLocation ?? location
            let previousGeometry = gestureStartTransform.geometry(canvasSize: canvasSize, imageSize: imageSize)
            let newScale = min(max(gestureStartTransform.scale * magnification, minScale), maxScale)
            var nextTransform = CanvasTransform(scale: newScale, offset: gestureStartTransform.offset)
            let nextGeometry = nextTransform.geometry(canvasSize: canvasSize, imageSize: imageSize)
            guard previousGeometry.cellSize > 0, nextGeometry.cellSize > 0 else {
                transform = nextTransform
                return
            }

            let localX = (anchorLocation.x - previousGeometry.origin.x) / previousGeometry.cellSize
            let localY = (anchorLocation.y - previousGeometry.origin.y) / previousGeometry.cellSize
            let nextOrigin = nextGeometry.origin
            nextTransform.offset = CGSize(
                width: nextTransform.offset.width + anchorLocation.x - (nextOrigin.x + localX * nextGeometry.cellSize),
                height: nextTransform.offset.height + anchorLocation.y - (nextOrigin.y + localY * nextGeometry.cellSize)
            )
            transform = nextTransform
        case .ended, .cancelled:
            gestureStartTransform = transform
            pinchStartLocation = nil
        }
    }

    private func handlePaintStroke(at point: CGPoint, phase: CanvasInputPhase, canvasSize: CGSize) {
        switch phase {
        case .began:
            lastStrokePixelIndex = nil
            onStrokePixel(-1, phase)
        case .changed:
            guard let pixelIndex = pixelIndex(at: point, canvasSize: canvasSize) else { return }
            guard lastStrokePixelIndex != pixelIndex else { return }
            lastStrokePixelIndex = pixelIndex
            onStrokePixel(pixelIndex, phase)
        case .ended, .cancelled:
            onStrokePixel(-1, phase)
            lastStrokePixelIndex = nil
        }
    }

    private func pixelIndex(at point: CGPoint, canvasSize: CGSize) -> Int? {
        let imageSize = PixelSize(width: document.width, height: document.height)
        guard let coordinate = transform.screenPointToPixel(point, canvasSize: canvasSize, imageSize: imageSize) else { return nil }
        let pixelIndex = coordinate.pixelIndex(in: imageSize)
        guard pixelIndex < document.targetColorIndexByPixel.count else { return nil }
        return pixelIndex
    }

    private func resetTransform() {
        transform = CanvasTransform()
        gestureStartTransform = transform
        pinchStartLocation = nil
        lastStrokePixelIndex = nil
    }
}
