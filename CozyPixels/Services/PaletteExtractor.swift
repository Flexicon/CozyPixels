import CoreGraphics
import Foundation

nonisolated struct RGBAPixel: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

nonisolated enum PaletteExtractorError: Error, Equatable, Sendable {
    case tooManyColors(count: Int, maximum: Int)
}

nonisolated struct PaletteExtractionResult: Equatable, Sendable {
    var palette: [PaletteColor]
    var targetColorIndexByPixel: [UInt16]
    var paintablePixelCount: Int
}

nonisolated struct PaletteExtractor: Sendable {
    static let defaultMaxPaletteColors = 32

    let maxPaletteColors: Int

    init(maxPaletteColors: Int = Self.defaultMaxPaletteColors) {
        self.maxPaletteColors = maxPaletteColors
    }

    func extract(from pixels: [RGBAPixel]) throws -> PaletteExtractionResult {
        let paintableColors = Set(pixels.filter { $0.alpha != 0 })

        guard paintableColors.count <= maxPaletteColors else {
            throw PaletteExtractorError.tooManyColors(count: paintableColors.count, maximum: maxPaletteColors)
        }

        let sortedColors = paintableColors.sorted(by: Self.sortsBefore)
        let palette = sortedColors.enumerated().map { index, color in
            PaletteColor(id: index + 1, red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }
        let colorIDs = Dictionary(uniqueKeysWithValues: zip(sortedColors, palette.map(\.id)))
        let targetColorIndexByPixel = pixels.map { pixel -> UInt16 in
            guard pixel.alpha != 0, let id = colorIDs[pixel] else { return 0 }
            return UInt16(id)
        }

        return PaletteExtractionResult(
            palette: palette,
            targetColorIndexByPixel: targetColorIndexByPixel,
            paintablePixelCount: pixels.filter { $0.alpha != 0 }.count
        )
    }

    private static func sortsBefore(_ lhs: RGBAPixel, _ rhs: RGBAPixel) -> Bool {
        let lhsHSB = hsb(for: lhs)
        let rhsHSB = hsb(for: rhs)

        if lhsHSB.hue != rhsHSB.hue { return lhsHSB.hue < rhsHSB.hue }
        if lhsHSB.saturation != rhsHSB.saturation { return lhsHSB.saturation < rhsHSB.saturation }
        if lhsHSB.brightness != rhsHSB.brightness { return lhsHSB.brightness < rhsHSB.brightness }
        if lhs.red != rhs.red { return lhs.red < rhs.red }
        if lhs.green != rhs.green { return lhs.green < rhs.green }
        if lhs.blue != rhs.blue { return lhs.blue < rhs.blue }
        return lhs.alpha < rhs.alpha
    }

    private static func hsb(for pixel: RGBAPixel) -> (hue: Double, saturation: Double, brightness: Double) {
        let red = Double(pixel.red) / 255
        let green = Double(pixel.green) / 255
        let blue = Double(pixel.blue) / 255
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maxValue == green {
            hue = (((blue - red) / delta) + 2) / 6
        } else {
            hue = (((red - green) / delta) + 4) / 6
        }

        return (hue < 0 ? hue + 1 : hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }
}
