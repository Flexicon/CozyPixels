import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageImportError: Error, Equatable, Sendable {
    case unsupportedImageData
    case invalidDimensions(width: Int, height: Int)
    case imageTooLarge(width: Int, height: Int, maximum: Int)
    case sourceImageTooLarge(width: Int, height: Int, maximumLongestSide: Int, maximumShortestSide: Int)
    case cannotCreateBitmapContext
    case cannotReadPixels
    case tooManyColors(count: Int, maximum: Int)
}

nonisolated struct ImageImportResult: Equatable, Sendable {
    var document: PaintingDocument
    var exceedsRecommendedSize: Bool
    var paintablePixelCount: Int
    var originalWidth: Int
    var originalHeight: Int
    var wasResized: Bool
    var wasQuantized: Bool
}

nonisolated struct ImageImportService: Sendable {
    static let recommendedMaxDimension = 64
    static let hardMaxDimension = 64
    static let maximumSourceLongestSide = 2560
    static let maximumSourceShortestSide = 1440

    let recommendedMaxDimension: Int
    let hardMaxDimension: Int
    let maximumSourceLongestSide: Int
    let maximumSourceShortestSide: Int
    let paletteExtractor: PaletteExtractor
    let colorQuantizer: ColorQuantizer

    init(
        recommendedMaxDimension: Int = Self.recommendedMaxDimension,
        hardMaxDimension: Int = Self.hardMaxDimension,
        maximumSourceLongestSide: Int = Self.maximumSourceLongestSide,
        maximumSourceShortestSide: Int = Self.maximumSourceShortestSide,
        paletteExtractor: PaletteExtractor = PaletteExtractor(),
        colorQuantizer: ColorQuantizer = ColorQuantizer()
    ) {
        self.recommendedMaxDimension = recommendedMaxDimension
        self.hardMaxDimension = hardMaxDimension
        self.maximumSourceLongestSide = maximumSourceLongestSide
        self.maximumSourceShortestSide = maximumSourceShortestSide
        self.paletteExtractor = paletteExtractor
        self.colorQuantizer = colorQuantizer
    }

    func importImageData(_ data: Data) throws -> ImageImportResult {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageImportError.unsupportedImageData
        }

        return try importCGImage(image)
    }

    func importCGImage(_ image: CGImage) throws -> ImageImportResult {
        let originalWidth = image.width
        let originalHeight = image.height

        guard originalWidth > 0, originalHeight > 0 else {
            throw ImageImportError.invalidDimensions(width: originalWidth, height: originalHeight)
        }

        let sourceLongestSide = max(originalWidth, originalHeight)
        let sourceShortestSide = min(originalWidth, originalHeight)
        guard sourceLongestSide <= maximumSourceLongestSide, sourceShortestSide <= maximumSourceShortestSide else {
            throw ImageImportError.sourceImageTooLarge(
                width: originalWidth,
                height: originalHeight,
                maximumLongestSide: maximumSourceLongestSide,
                maximumShortestSide: maximumSourceShortestSide
            )
        }

        let outputSize = outputSize(forWidth: originalWidth, height: originalHeight)
        let pixels = try rgbaPixels(from: image, width: outputSize.width, height: outputSize.height)
        let wasResized = outputSize.width != originalWidth || outputSize.height != originalHeight

        do {
            let extraction = try extraction(from: pixels)
            let document = PaintingDocument(
                width: outputSize.width,
                height: outputSize.height,
                palette: extraction.palette,
                targetColorIndexByPixel: extraction.targetColorIndexByPixel,
                correctPaintedBitset: Bitset(bitCount: outputSize.width * outputSize.height).data
            )

            return ImageImportResult(
                document: document,
                exceedsRecommendedSize: outputSize.width > recommendedMaxDimension || outputSize.height > recommendedMaxDimension,
                paintablePixelCount: extraction.paintablePixelCount,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                wasResized: wasResized,
                wasQuantized: extraction.wasQuantized
            )
        } catch PaletteExtractorError.tooManyColors(let count, let maximum) {
            throw ImageImportError.tooManyColors(count: count, maximum: maximum)
        }
    }

    private func outputSize(forWidth width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > hardMaxDimension || height > hardMaxDimension else { return (width, height) }

        let scale = Double(hardMaxDimension) / Double(max(width, height))
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private func extraction(from pixels: [RGBAPixel]) throws -> (palette: [PaletteColor], targetColorIndexByPixel: [UInt16], paintablePixelCount: Int, wasQuantized: Bool) {
        do {
            let extraction = try paletteExtractor.extract(from: pixels)
            return (extraction.palette, extraction.targetColorIndexByPixel, extraction.paintablePixelCount, false)
        } catch PaletteExtractorError.tooManyColors {
            let quantizedPixels = colorQuantizer.quantize(pixels, maxColors: paletteExtractor.maxPaletteColors)
            let extraction = try paletteExtractor.extract(from: quantizedPixels)
            return (extraction.palette, extraction.targetColorIndexByPixel, extraction.paintablePixelCount, true)
        }
    }

    private func rgbaPixels(from image: CGImage, width: Int, height: Int) throws -> [RGBAPixel] {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageImportError.cannotCreateBitmapContext
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard bytes.count == width * height * bytesPerPixel else {
            throw ImageImportError.cannotReadPixels
        }

        return stride(from: 0, to: bytes.count, by: bytesPerPixel).map { index in
            RGBAPixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
        }
    }
}
