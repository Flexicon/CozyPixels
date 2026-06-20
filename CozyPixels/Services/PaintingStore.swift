import Foundation

nonisolated enum PaintingStoreError: Error, Equatable, Sendable {
    case missingPaintingDocument(URL)
    case corruptPaintingDocument(URL)
}

nonisolated struct PaintingStore {
    static let paintingDocumentFilename = "painting.json"
    static let previewFilename = "preview.png"

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder

        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootDirectory = applicationSupport.appending(path: "Paintings", directoryHint: .isDirectory)
        }

        try fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    func directoryURL(for paintingID: UUID) -> URL {
        rootDirectory.appending(path: paintingID.uuidString, directoryHint: .isDirectory)
    }

    func paintingDocumentURL(for paintingID: UUID) -> URL {
        directoryURL(for: paintingID).appending(path: Self.paintingDocumentFilename, directoryHint: .notDirectory)
    }

    func previewURL(for paintingID: UUID) -> URL {
        directoryURL(for: paintingID).appending(path: Self.previewFilename, directoryHint: .notDirectory)
    }

    func savePaintingDocument(_ document: PaintingDocument, for paintingID: UUID) throws {
        let directoryURL = directoryURL(for: paintingID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(document)
        try data.write(to: paintingDocumentURL(for: paintingID), options: .atomic)
    }

    func loadPaintingDocument(for paintingID: UUID) throws -> PaintingDocument {
        let url = paintingDocumentURL(for: paintingID)

        guard fileManager.fileExists(atPath: url.path) else {
            throw PaintingStoreError.missingPaintingDocument(url)
        }

        let data = try Data(contentsOf: url)

        do {
            return try decoder.decode(PaintingDocument.self, from: data)
        } catch {
            throw PaintingStoreError.corruptPaintingDocument(url)
        }
    }

    func resetPaintingDocument(for paintingID: UUID) throws -> PaintingDocument {
        var document = try loadPaintingDocument(for: paintingID)
        document.correctPaintedBitset = Bitset(bitCount: document.width * document.height).data
        document.wrongAttempts.removeAll()
        try savePaintingDocument(document, for: paintingID)
        return document
    }

    func savePreviewPNG(_ data: Data, for paintingID: UUID) throws {
        let directoryURL = directoryURL(for: paintingID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: previewURL(for: paintingID), options: .atomic)
    }

    func deletePaintingDirectory(for paintingID: UUID) throws {
        let directoryURL = directoryURL(for: paintingID)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try fileManager.removeItem(at: directoryURL)
    }
}
