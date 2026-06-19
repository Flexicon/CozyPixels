import Foundation

nonisolated struct GalleryItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var tags: [String]
    var assetName: String
    var difficulty: String

    init(id: String, title: String, tags: [String], assetName: String, difficulty: String) {
        self.id = id
        self.title = title
        self.tags = tags
        self.assetName = assetName
        self.difficulty = difficulty
    }
}
