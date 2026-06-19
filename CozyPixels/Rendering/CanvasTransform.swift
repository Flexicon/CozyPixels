import CoreGraphics
import Foundation

nonisolated struct CanvasTransform: Equatable, Sendable {
    var scale: CGFloat
    var offset: CGSize

    init(scale: CGFloat = 1, offset: CGSize = .zero) {
        self.scale = scale
        self.offset = offset
    }

    func geometry(canvasSize: CGSize, imageSize: PixelSize) -> PixelGeometry {
        PixelGeometry(imageSize: imageSize, canvasSize: canvasSize, scale: scale, offset: offset)
    }

    func screenPointToPixel(
        _ point: CGPoint,
        canvasSize: CGSize,
        imageSize: PixelSize
    ) -> PixelCoordinate? {
        let geometry = geometry(canvasSize: canvasSize, imageSize: imageSize)
        guard geometry.cellSize > 0 else { return nil }

        let localX = point.x - geometry.origin.x
        let localY = point.y - geometry.origin.y
        guard localX >= 0, localY >= 0 else { return nil }

        let x = Int(localX / geometry.cellSize)
        let y = Int(localY / geometry.cellSize)
        guard (0..<imageSize.width).contains(x), (0..<imageSize.height).contains(y) else { return nil }

        return PixelCoordinate(x: x, y: y)
    }
}
