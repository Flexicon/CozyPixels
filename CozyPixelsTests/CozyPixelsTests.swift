//
//  CozyPixelsTests.swift
//  CozyPixelsTests
//
//  Created by Michał Repeć on 19/06/2026.
//

import Testing
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

@testable import CozyPixels

struct CozyPixelsTests {

    @Test func paintingCanBeInsertedIntoSwiftData() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Painting.self, configurations: configuration)
        let context = ModelContext(container)

        let painting = Painting(
            title: "Test Painting",
            sourceType: .imported,
            width: 2,
            height: 2,
            paletteColorCount: 2,
            totalPaintablePixelCount: 4
        )

        context.insert(painting)
        try context.save()

        let paintings = try context.fetch(FetchDescriptor<Painting>())
        #expect(paintings.count == 1)
        #expect(paintings[0].title == "Test Painting")
        #expect(paintings[0].sourceTypeRawValue == PaintingSourceType.imported.rawValue)
    }

    @Test func paintingDocumentEncodesAndDecodes() throws {
        let date = Date(timeIntervalSince1970: 1_800)
        let document = PaintingDocument(
            width: 2,
            height: 2,
            palette: [
                PaletteColor(id: 1, red: 255, green: 0, blue: 0),
                PaletteColor(id: 2, red: 0, green: 0, blue: 255)
            ],
            targetColorIndexByPixel: [1, 2, 2, 1],
            correctPaintedBitset: Data([0b0000_0101]),
            wrongAttempts: [
                WrongAttempt(pixelIndex: 1, attemptedPaletteColorID: 1, createdAt: date)
            ]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(PaintingDocument.self, from: encoded)

        #expect(decoded == document)
    }

    @Test func bitsetCanSetClearAndGetByIndex() {
        var bitset = Bitset(bitCount: 10)

        #expect(bitset.contains(0) == false)
        #expect(bitset.contains(9) == false)

        bitset.set(0)
        bitset.set(9)

        #expect(bitset.contains(0))
        #expect(bitset.contains(9))
        #expect(bitset.contains(5) == false)

        bitset.set(0, to: false)

        #expect(bitset.contains(0) == false)
        #expect(bitset.contains(9))
    }

    @Test func bitsetCanRoundTripExistingData() {
        let original = Data([0b1000_0001, 0b0000_0010])
        let bitset = Bitset(data: original, bitCount: 10)

        #expect(bitset.data == original)
        #expect(bitset.contains(0))
        #expect(bitset.contains(7))
        #expect(bitset.contains(9))
        #expect(bitset.contains(8) == false)
    }

    @Test func pixelIndexUsesRowMajorOrder() {
        let width = 8
        let x = 3
        let y = 4

        let pixelIndex = y * width + x

        #expect(pixelIndex == 35)
    }

    @Test func paintingStoreSavesAndLoadsPaintingDocument() throws {
        let rootDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = try PaintingStore(rootDirectory: rootDirectory)
        let paintingID = UUID()
        let document = samplePaintingDocument()

        try store.savePaintingDocument(document, for: paintingID)
        let loadedDocument = try store.loadPaintingDocument(for: paintingID)

        #expect(loadedDocument == document)
        #expect(FileManager.default.fileExists(atPath: store.paintingDocumentURL(for: paintingID).path))
    }

    @Test func paintingStoreReportsMissingPaintingDocument() throws {
        let rootDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = try PaintingStore(rootDirectory: rootDirectory)
        let paintingID = UUID()

        do {
            _ = try store.loadPaintingDocument(for: paintingID)
            Issue.record("Expected missing painting document error")
        } catch PaintingStoreError.missingPaintingDocument(let url) {
            #expect(url == store.paintingDocumentURL(for: paintingID))
        }
    }

    @Test func paintingStoreReportsCorruptPaintingDocument() throws {
        let rootDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = try PaintingStore(rootDirectory: rootDirectory)
        let paintingID = UUID()
        let directoryURL = store.directoryURL(for: paintingID)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.paintingDocumentURL(for: paintingID))

        do {
            _ = try store.loadPaintingDocument(for: paintingID)
            Issue.record("Expected corrupt painting document error")
        } catch PaintingStoreError.corruptPaintingDocument(let url) {
            #expect(url == store.paintingDocumentURL(for: paintingID))
        }
    }

    @Test func paintingStoreSavesPreviewPNG() throws {
        let rootDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = try PaintingStore(rootDirectory: rootDirectory)
        let paintingID = UUID()
        let previewData = Data([0x89, 0x50, 0x4E, 0x47])

        try store.savePreviewPNG(previewData, for: paintingID)

        #expect(try Data(contentsOf: store.previewURL(for: paintingID)) == previewData)
    }

    @Test func paintingStoreDeletesPaintingDirectory() throws {
        let rootDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = try PaintingStore(rootDirectory: rootDirectory)
        let paintingID = UUID()

        try store.savePaintingDocument(samplePaintingDocument(), for: paintingID)
        try store.savePreviewPNG(Data([1, 2, 3]), for: paintingID)

        try store.deletePaintingDirectory(for: paintingID)

        #expect(FileManager.default.fileExists(atPath: store.directoryURL(for: paintingID).path) == false)
    }

    @Test func paletteExtractorExtractsExactColorsAndPixelIDs() throws {
        let extractor = PaletteExtractor()
        let pixels = [
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 255, blue: 0, alpha: 255),
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 0, blue: 0, alpha: 0)
        ]

        let result = try extractor.extract(from: pixels)

        #expect(result.palette.count == 2)
        #expect(result.targetColorIndexByPixel[0] == result.targetColorIndexByPixel[2])
        #expect(result.targetColorIndexByPixel[3] == 0)
        #expect(result.paintablePixelCount == 3)
    }

    @Test func paletteExtractorSortsDeterministicallyByHueSaturationBrightnessAndRGB() throws {
        let extractor = PaletteExtractor()
        let pixels = [
            RGBAPixel(red: 0, green: 0, blue: 255, alpha: 255),
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 128, green: 128, blue: 128, alpha: 255),
            RGBAPixel(red: 0, green: 255, blue: 0, alpha: 255)
        ]

        let result = try extractor.extract(from: pixels)

        #expect(result.palette.map { [$0.red, $0.green, $0.blue] } == [
            [128, 128, 128],
            [255, 0, 0],
            [0, 255, 0],
            [0, 0, 255]
        ])
        #expect(result.palette.map(\.id) == [1, 2, 3, 4])
    }

    @Test func paletteExtractorRejectsTooManyColors() throws {
        let extractor = PaletteExtractor(maxPaletteColors: 2)
        let pixels = [
            RGBAPixel(red: 1, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 2, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 3, green: 0, blue: 0, alpha: 255)
        ]

        do {
            _ = try extractor.extract(from: pixels)
            Issue.record("Expected too many colors error")
        } catch PaletteExtractorError.tooManyColors(let count, let maximum) {
            #expect(count == 3)
            #expect(maximum == 2)
        }
    }

    @Test func imageImportServiceImportsSmallPNGData() throws {
        let data = try pngData(width: 2, height: 2, pixels: [
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 255, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 0, blue: 255, alpha: 255),
            RGBAPixel(red: 0, green: 0, blue: 0, alpha: 0)
        ])

        let result = try ImageImportService().importImageData(data)

        #expect(result.document.width == 2)
        #expect(result.document.height == 2)
        #expect(result.document.palette.count == 3)
        #expect(result.document.targetColorIndexByPixel.count == 4)
        #expect(result.document.targetColorIndexByPixel[3] == 0)
        #expect(result.paintablePixelCount == 3)
        #expect(result.exceedsRecommendedSize == false)
        #expect(result.originalWidth == 2)
        #expect(result.originalHeight == 2)
        #expect(result.wasResized == false)
        #expect(result.wasQuantized == false)
    }

    @Test func imageImportServiceResizesLandscapeImageToPlayableLimit() throws {
        let image = try solidCGImage(width: 1280, height: 720)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.width == 64)
        #expect(result.document.height == 36)
        #expect(result.originalWidth == 1280)
        #expect(result.originalHeight == 720)
        #expect(result.wasResized)
    }

    @Test func imageImportServiceResizesPortraitImageToPlayableLimit() throws {
        let image = try solidCGImage(width: 720, height: 1280)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.width == 36)
        #expect(result.document.height == 64)
        #expect(result.wasResized)
    }

    @Test func imageImportServiceDoesNotResizeImagesWithinPlayableLimit() throws {
        let image = try solidCGImage(width: 60, height: 50)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.width == 60)
        #expect(result.document.height == 50)
        #expect(result.wasResized == false)
    }

    @Test func imageImportServiceResizesImagesAboveNewPlayableLimit() throws {
        let image = try solidCGImage(width: 128, height: 128)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.width == 64)
        #expect(result.document.height == 64)
        #expect(result.wasResized)
    }

    @Test func imageImportServiceDoesNotFlagResizedImagesAtRecommendedSize() throws {
        let image = try cgImage(width: 65, height: 1, pixels: Array(repeating: RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255), count: 65))

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.width == 64)
        #expect(result.exceedsRecommendedSize == false)
    }

    @Test func imageImportServiceRejectsImagesAboveSourceLimit() throws {
        let image = try solidCGImage(width: 4032, height: 3024)

        do {
            _ = try ImageImportService().importCGImage(image)
            Issue.record("Expected oversized image error")
        } catch ImageImportError.sourceImageTooLarge(let width, let height, let maximumLongestSide, let maximumShortestSide) {
            #expect(width == 4032)
            #expect(height == 3024)
            #expect(maximumLongestSide == 2560)
            #expect(maximumShortestSide == 1440)
        }
    }

    @Test func imageImportServiceImportsTrustedImagesAboveSourceLimit() throws {
        let data = try pngData(width: 72, height: 72, pixels: Array(repeating: RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255), count: 72 * 72))
        let service = ImageImportService(maximumSourceLongestSide: 64, maximumSourceShortestSide: 64)

        let result = try service.importTrustedImageData(data)

        #expect(result.document.width == 64)
        #expect(result.document.height == 64)
        #expect(result.originalWidth == 72)
        #expect(result.originalHeight == 72)
        #expect(result.wasResized)
    }

    @Test func imageImportServiceQuantizesTooManyColors() throws {
        let pixels = (0..<33).map { RGBAPixel(red: UInt8($0), green: 0, blue: 0, alpha: 255) }
        let image = try cgImage(width: 33, height: 1, pixels: pixels)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.palette.count <= 32)
        #expect(result.wasQuantized)
    }

    @Test func imageImportServiceKeepsTransparentPixelsUnpaintableAfterQuantization() throws {
        var pixels = (0..<33).map { RGBAPixel(red: UInt8($0), green: 0, blue: 0, alpha: 255) }
        pixels.append(RGBAPixel(red: 255, green: 255, blue: 255, alpha: 0))
        let image = try cgImage(width: 34, height: 1, pixels: pixels)

        let result = try ImageImportService().importCGImage(image)

        #expect(result.document.targetColorIndexByPixel[33] == 0)
        #expect(result.paintablePixelCount == 33)
    }

    @Test func colorQuantizerIsDeterministic() {
        let pixels = variedPixels(count: 80)
        let quantizer = ColorQuantizer()

        #expect(quantizer.quantize(pixels, maxColors: 16) == quantizer.quantize(pixels, maxColors: 16))
    }

    @Test func colorQuantizerKeepsLowColorPixelArtUnchanged() {
        let pixels = [
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 255, blue: 0, alpha: 255),
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255),
            RGBAPixel(red: 0, green: 0, blue: 0, alpha: 0)
        ]

        #expect(ColorQuantizer().quantize(pixels, maxColors: 32) == pixels)
    }

    @Test func canvasTransformMapsScreenPointToPixel() {
        let transform = CanvasTransform()
        let coordinate = transform.screenPointToPixel(
            CGPoint(x: 150, y: 150),
            canvasSize: CGSize(width: 200, height: 200),
            imageSize: PixelSize(width: 4, height: 4)
        )

        #expect(coordinate == PixelCoordinate(x: 3, y: 3))
        #expect(coordinate?.pixelIndex(in: PixelSize(width: 4, height: 4)) == 15)
    }

    @Test func canvasTransformReturnsNilOutsideImageBounds() {
        let transform = CanvasTransform(scale: 1, offset: CGSize(width: 20, height: 0))
        let coordinate = transform.screenPointToPixel(
            CGPoint(x: 10, y: 50),
            canvasSize: CGSize(width: 100, height: 100),
            imageSize: PixelSize(width: 2, height: 2)
        )

        #expect(coordinate == nil)
    }

    @Test func paintingEngineCorrectPaintIncrementsProgressOnce() {
        var document = unpaintedPaintingDocument()
        let engine = PaintingEngine()

        let firstResult = engine.paintPixel(at: 0, selectedPaletteColorID: 1, in: &document)
        let secondResult = engine.paintPixel(at: 0, selectedPaletteColorID: 1, in: &document)

        #expect(firstResult == .changed(PaintPixelChange(pixelIndex: 0, completedDelta: 1)))
        #expect(secondResult == .unchanged)
        #expect(Bitset(data: document.correctPaintedBitset, bitCount: 4).contains(0))
    }

    @Test func paintingEngineWrongPaintPersistsAttempt() {
        var document = unpaintedPaintingDocument()
        document.wrongAttempts.removeAll()

        let result = PaintingEngine().paintPixel(at: 0, selectedPaletteColorID: 2, in: &document)

        #expect(result == .changed(PaintPixelChange(pixelIndex: 0, completedDelta: 0)))
        #expect(document.wrongAttempts.count == 1)
        #expect(document.wrongAttempts.first?.pixelIndex == 0)
        #expect(document.wrongAttempts.first?.attemptedPaletteColorID == 2)
    }

    @Test func paintingEngineDuplicateWrongAttemptIsIgnored() {
        var document = unpaintedPaintingDocument()
        document.wrongAttempts = [WrongAttempt(pixelIndex: 0, attemptedPaletteColorID: 2)]

        let result = PaintingEngine().paintPixel(at: 0, selectedPaletteColorID: 2, in: &document)

        #expect(result == .unchanged)
        #expect(document.wrongAttempts.count == 1)
    }

    @Test func paintingEngineCorrectPaintRemovesWrongAttempt() {
        let wrongAttempt = WrongAttempt(pixelIndex: 0, attemptedPaletteColorID: 2, createdAt: Date(timeIntervalSince1970: 50))
        var document = unpaintedPaintingDocument()
        document.wrongAttempts = [wrongAttempt]

        let result = PaintingEngine().paintPixel(at: 0, selectedPaletteColorID: 1, in: &document)

        #expect(result == .changed(PaintPixelChange(pixelIndex: 0, completedDelta: 1, previousWrongAttempt: wrongAttempt)))
        #expect(document.wrongAttempts.isEmpty)
        #expect(Bitset(data: document.correctPaintedBitset, bitCount: 4).contains(0))
    }

    @Test func paintingEngineWrongPaintOverCorrectPixelReopensProgress() {
        var document = unpaintedPaintingDocument()
        var bitset = Bitset(data: document.correctPaintedBitset, bitCount: 4)
        bitset.set(0)
        document.correctPaintedBitset = bitset.data

        let result = PaintingEngine().paintPixel(at: 0, selectedPaletteColorID: 2, in: &document)

        #expect(result == .changed(PaintPixelChange(pixelIndex: 0, completedDelta: -1)))
        #expect(Bitset(data: document.correctPaintedBitset, bitCount: 4).contains(0) == false)
        #expect(document.wrongAttempts.count == 1)
        #expect(document.wrongAttempts.first?.pixelIndex == 0)
        #expect(document.wrongAttempts.first?.attemptedPaletteColorID == 2)
    }

    @Test func importedImageCreatesPaintingImmediately() throws {
        let result = try ImageImportService().importCGImage(try cgImage(width: 1, height: 1, pixels: [
            RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255)
        ]))

        let painting = Painting(
            title: "Imported",
            sourceType: .imported,
            width: result.document.width,
            height: result.document.height,
            paletteColorCount: result.document.palette.count,
            completedPixelCount: 0,
            totalPaintablePixelCount: result.paintablePixelCount
        )

        #expect(painting.sourceTypeRawValue == PaintingSourceType.imported.rawValue)
        #expect(painting.completedPixelCount == 0)
        #expect(painting.totalPaintablePixelCount == 1)
    }

    @Test func galleryImageCreatesPaintingOnlyAfterFirstCorrectPaint() {
        var document = unpaintedPaintingDocument()
        let galleryItem = GalleryItem(id: "sample", title: "Sample", tags: ["easy"], assetName: "sample", difficulty: "easy")
        let result = PaintingEngine().paintPixel(at: 0, selectedPaletteColorID: 1, in: &document)

        let painting: Painting?
        if case .changed(let change) = result, change.completedDelta == 1 {
            painting = Painting(
                title: galleryItem.title,
                sourceType: .gallery,
                width: document.width,
                height: document.height,
                paletteColorCount: document.palette.count,
                completedPixelCount: 1,
                totalPaintablePixelCount: 4,
                isCompleted: false
            )
        } else {
            painting = nil
        }

        #expect(painting?.sourceTypeRawValue == PaintingSourceType.gallery.rawValue)
        #expect(painting?.completedPixelCount == 1)
    }

}

private func samplePaintingDocument() -> PaintingDocument {
    PaintingDocument(
        width: 2,
        height: 2,
        palette: [
            PaletteColor(id: 1, red: 255, green: 0, blue: 0),
            PaletteColor(id: 2, red: 0, green: 0, blue: 255)
        ],
        targetColorIndexByPixel: [1, 2, 2, 1],
        correctPaintedBitset: Data([0b0000_0101]),
        wrongAttempts: [
            WrongAttempt(pixelIndex: 1, attemptedPaletteColorID: 2, createdAt: Date(timeIntervalSince1970: 1_800))
        ]
    )
}

private func unpaintedPaintingDocument() -> PaintingDocument {
    PaintingDocument(
        width: 2,
        height: 2,
        palette: [
            PaletteColor(id: 1, red: 255, green: 0, blue: 0),
            PaletteColor(id: 2, red: 0, green: 0, blue: 255)
        ],
        targetColorIndexByPixel: [1, 2, 2, 1],
        correctPaintedBitset: Bitset(bitCount: 4).data,
        wrongAttempts: []
    )
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "CozyPixelsTests", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cgImage(width: Int, height: Int, pixels: [RGBAPixel]) throws -> CGImage {
    #expect(pixels.count == width * height)
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var bytes = [UInt8]()
    bytes.reserveCapacity(pixels.count * bytesPerPixel)

    for pixel in pixels {
        bytes.append(pixel.red)
        bytes.append(pixel.green)
        bytes.append(pixel.blue)
        bytes.append(pixel.alpha)
    }

    let provider = CGDataProvider(data: Data(bytes) as CFData)
    let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        provider: try #require(provider),
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )

    return try #require(image)
}

private func solidCGImage(width: Int, height: Int) throws -> CGImage {
    try cgImage(
        width: width,
        height: height,
        pixels: Array(repeating: RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255), count: width * height)
    )
}

private func variedPixels(count: Int) -> [RGBAPixel] {
    var pixels = [RGBAPixel]()
    pixels.reserveCapacity(count)
    for index in 0..<count {
        pixels.append(RGBAPixel(
            red: UInt8((index * 3) % 256),
            green: UInt8((index * 5) % 256),
            blue: UInt8((index * 7) % 256),
            alpha: 255
        ))
    }
    return pixels
}

private func pngData(width: Int, height: Int, pixels: [RGBAPixel]) throws -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    CGImageDestinationAddImage(try #require(destination), try cgImage(width: width, height: height, pixels: pixels), nil)
    #expect(CGImageDestinationFinalize(try #require(destination)))
    return data as Data
}
