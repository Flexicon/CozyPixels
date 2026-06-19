//
//  CozyPixelsTests.swift
//  CozyPixelsTests
//
//  Created by Michał Repeć on 19/06/2026.
//

import Testing
import Foundation
import SwiftData

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

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "CozyPixelsTests", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
