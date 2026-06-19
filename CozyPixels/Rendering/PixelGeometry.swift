import CoreGraphics
import Foundation

nonisolated struct PixelSize: Equatable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

nonisolated struct PixelCoordinate: Equatable, Sendable {
    var x: Int
    var y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    func pixelIndex(in size: PixelSize) -> Int {
        y * size.width + x
    }
}

nonisolated struct PixelGeometry: Equatable, Sendable {
    var imageSize: PixelSize
    var canvasSize: CGSize
    var scale: CGFloat
    var offset: CGSize

    var cellSize: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        let fitScale = min(canvasSize.width / CGFloat(imageSize.width), canvasSize.height / CGFloat(imageSize.height))
        return max(0, fitScale * scale)
    }

    var contentSize: CGSize {
        CGSize(width: CGFloat(imageSize.width) * cellSize, height: CGFloat(imageSize.height) * cellSize)
    }

    var origin: CGPoint {
        CGPoint(
            x: (canvasSize.width - contentSize.width) / 2 + offset.width,
            y: (canvasSize.height - contentSize.height) / 2 + offset.height
        )
    }

    func rect(for coordinate: PixelCoordinate) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(coordinate.x) * cellSize,
            y: origin.y + CGFloat(coordinate.y) * cellSize,
            width: cellSize,
            height: cellSize
        )
    }
}
