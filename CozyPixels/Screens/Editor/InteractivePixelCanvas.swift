import SwiftUI
import UIKit

struct InteractivePixelCanvas: View {
    let document: PaintingDocument
    let renderCache: PixelCanvasRenderCache
    let pixelImage: CGImage?
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
    @State private var lastStrokeCoordinate: PixelCoordinate?
    @State private var panCommitter = CanvasPanCommitter()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PixelCanvasView(
                    state: PixelCanvasRenderState(
                        document: document,
                        cache: renderCache,
                        pixelImage: pixelImage,
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
                    onPan: { translation, phase, source in
                        handlePan(translation: translation, phase: phase, source: source)
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
            .onDisappear {
                panCommitter.stop()
            }
        }
    }

    private func handlePan(translation: CGSize, phase: CanvasInputPhase, source: CanvasInputSource) {
        switch phase {
        case .began:
            panCommitter.stop()
            gestureStartTransform = transform
            panCommitter.begin()
        case .changed:
            panCommitter.update(translation: translation) { latestTranslation in
                commitPan(translation: latestTranslation)
            }
        case .ended, .cancelled:
            panCommitter.end { latestTranslation in
                commitPan(translation: latestTranslation)
            }
            gestureStartTransform = transform
        }
    }

    private func commitPan(translation: CGSize) {
        let nextOffset = CGSize(
            width: gestureStartTransform.offset.width + translation.width,
            height: gestureStartTransform.offset.height + translation.height
        )
        guard abs(transform.offset.width - nextOffset.width) >= 0.25 || abs(transform.offset.height - nextOffset.height) >= 0.25 else { return }
        transform.offset = nextOffset
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
            lastStrokeCoordinate = nil
            onStrokePixel(-1, phase)
        case .changed:
            let imageSize = PixelSize(width: document.width, height: document.height)
            guard let coordinate = pixelCoordinate(at: point, canvasSize: canvasSize, imageSize: imageSize) else { return }
            let coordinates: [PixelCoordinate]
            if let lastStrokeCoordinate {
                coordinates = pixelsCrossed(from: lastStrokeCoordinate, to: coordinate, bounds: imageSize).dropFirst().map { $0 }
            } else {
                coordinates = [coordinate]
            }
            guard !coordinates.isEmpty else { return }
            lastStrokeCoordinate = coordinate
            for coordinate in coordinates {
                onStrokePixel(coordinate.pixelIndex(in: imageSize), phase)
            }
        case .ended, .cancelled:
            onStrokePixel(-1, phase)
            lastStrokeCoordinate = nil
        }
    }

    private func pixelIndex(at point: CGPoint, canvasSize: CGSize) -> Int? {
        let imageSize = PixelSize(width: document.width, height: document.height)
        guard let coordinate = pixelCoordinate(at: point, canvasSize: canvasSize, imageSize: imageSize) else { return nil }
        let pixelIndex = coordinate.pixelIndex(in: imageSize)
        guard pixelIndex < document.targetColorIndexByPixel.count else { return nil }
        return pixelIndex
    }

    private func pixelCoordinate(at point: CGPoint, canvasSize: CGSize, imageSize: PixelSize) -> PixelCoordinate? {
        guard let coordinate = transform.screenPointToPixel(point, canvasSize: canvasSize, imageSize: imageSize) else { return nil }
        guard coordinate.pixelIndex(in: imageSize) < document.targetColorIndexByPixel.count else { return nil }
        return coordinate
    }

    private func resetTransform() {
        transform = CanvasTransform()
        gestureStartTransform = transform
        pinchStartLocation = nil
        lastStrokeCoordinate = nil
        panCommitter.stop()
    }
}

@MainActor
private final class CanvasPanCommitter {
    private var displayLink: CADisplayLink?
    private var latestTranslation = CGSize.zero
    private var hasPendingTranslation = false
    private var commit: ((CGSize) -> Void)?

    func begin() {
        latestTranslation = .zero
        hasPendingTranslation = false
    }

    func update(translation: CGSize, commit: @escaping (CGSize) -> Void) {
        latestTranslation = translation
        hasPendingTranslation = true
        self.commit = commit
        startIfNeeded()
    }

    func end(commit: (CGSize) -> Void) {
        if hasPendingTranslation {
            commit(latestTranslation)
        }
        stop()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        commit = nil
        hasPendingTranslation = false
    }

    private func startIfNeeded() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func displayLinkDidFire() {
        guard hasPendingTranslation, let commit else { return }
        commit(latestTranslation)
        hasPendingTranslation = false
    }
}
