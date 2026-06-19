import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageImportError: Error, Equatable, Sendable {
    case unsupportedImageData
    case invalidDimensions(width: Int, height: Int)
    case imageTooLarge(width: Int, height: Int, maximum: Int)
    case cannotCreateBitmapContext
    case cannotReadPixels
    case tooManyColors(count: Int, maximum: Int)
}

nonisolated struct ImageImportResult: Equatable, Sendable {
    var document: PaintingDocument
    var exceedsRecommendedSize: Bool
    var paintablePixelCount: Int
}

nonisolated struct ImageImportService: Sendable {
    static let recommendedMaxDimension = 128
    static let hardMaxDimension = 256

    let recommendedMaxDimension: Int
    let hardMaxDimension: Int
    let paletteExtractor: PaletteExtractor

    init(
        recommendedMaxDimension: Int = Self.recommendedMaxDimension,
        hardMaxDimension: Int = Self.hardMaxDimension,
        paletteExtractor: PaletteExtractor = PaletteExtractor()
    ) {
        self.recommendedMaxDimension = recommendedMaxDimension
        self.hardMaxDimension = hardMaxDimension
        self.paletteExtractor = paletteExtractor
    }

    func importImageData(_ data: Data) throws -> ImageImportResult {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageImportError.unsupportedImageData
        }

        return try importCGImage(image)
    }

    func importCGImage(_ image: CGImage) throws -> ImageImportResult {
        let width = image.width
        let height = image.height

        guard width > 0, height > 0 else {
            throw ImageImportError.invalidDimensions(width: width, height: height)
        }

        guard width <= hardMaxDimension, height <= hardMaxDimension else {
            throw ImageImportError.imageTooLarge(width: width, height: height, maximum: hardMaxDimension)
        }

        let pixels = try rgbaPixels(from: image, width: width, height: height)

        do {
            let extraction = try paletteExtractor.extract(from: pixels)
            let document = PaintingDocument(
                width: width,
                height: height,
                palette: extraction.palette,
                targetColorIndexByPixel: extraction.targetColorIndexByPixel,
                correctPaintedBitset: Bitset(bitCount: width * height).data
            )

            return ImageImportResult(
                document: document,
                exceedsRecommendedSize: width > recommendedMaxDimension || height > recommendedMaxDimension,
                paintablePixelCount: extraction.paintablePixelCount
            )
        } catch PaletteExtractorError.tooManyColors(let count, let maximum) {
            throw ImageImportError.tooManyColors(count: count, maximum: maximum)
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
