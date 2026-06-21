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

    func isContained(in size: PixelSize) -> Bool {
        x >= 0 && x < size.width && y >= 0 && y < size.height
    }
}

nonisolated func pixelsCrossed(from start: PixelCoordinate, to end: PixelCoordinate, bounds: PixelSize? = nil) -> [PixelCoordinate] {
    let dx = abs(end.x - start.x)
    let dy = abs(end.y - start.y)
    let stepX = start.x == end.x ? 0 : (start.x < end.x ? 1 : -1)
    let stepY = start.y == end.y ? 0 : (start.y < end.y ? 1 : -1)

    var x = start.x
    var y = start.y
    var error = dx - dy
    var coordinates: [PixelCoordinate] = []

    while true {
        let coordinate = PixelCoordinate(x: x, y: y)
        if bounds.map({ coordinate.isContained(in: $0) }) ?? true {
            coordinates.append(coordinate)
        }

        if x == end.x, y == end.y { break }

        let doubledError = 2 * error
        if doubledError > -dy {
            error -= dy
            x += stepX
        }
        if doubledError < dx {
            error += dx
            y += stepY
        }
    }

    return coordinates
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

    func visiblePixelRange(in viewport: CGRect) -> (x: Range<Int>, y: Range<Int>)? {
        guard cellSize > 0 else { return nil }

        let origin = origin
        let minX = max(0, Int(floor((viewport.minX - origin.x) / cellSize)))
        let maxX = min(imageSize.width, Int(ceil((viewport.maxX - origin.x) / cellSize)))
        let minY = max(0, Int(floor((viewport.minY - origin.y) / cellSize)))
        let maxY = min(imageSize.height, Int(ceil((viewport.maxY - origin.y) / cellSize)))

        guard minX < maxX, minY < maxY else { return nil }
        return (minX..<maxX, minY..<maxY)
    }
}
