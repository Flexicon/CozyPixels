import Foundation

nonisolated enum GalleryStoreError: Error, Equatable, Sendable {
    case missingManifest
    case corruptManifest
    case missingAsset(String)
}

nonisolated struct GalleryStore: Sendable {
    static let manifestName = "gallery"
    static let manifestExtension = "json"
    static let resourceSubdirectory = "Resources/Gallery"

    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main, decoder: JSONDecoder = JSONDecoder()) {
        self.bundle = bundle
        self.decoder = decoder
    }

    func loadItems() throws -> [GalleryItem] {
        guard let url = resourceURL(for: Self.manifestName, withExtension: Self.manifestExtension) else {
            throw GalleryStoreError.missingManifest
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([GalleryItem].self, from: data)
        } catch {
            throw GalleryStoreError.corruptManifest
        }
    }

    func data(for item: GalleryItem) throws -> Data {
        guard let url = resourceURL(for: item.assetName, withExtension: "png") else {
            throw GalleryStoreError.missingAsset(item.assetName)
        }

        return try Data(contentsOf: url)
    }

    func resourceURL(for name: String, withExtension fileExtension: String) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension, subdirectory: Self.resourceSubdirectory)
            ?? bundle.url(forResource: name, withExtension: fileExtension)
    }
}
