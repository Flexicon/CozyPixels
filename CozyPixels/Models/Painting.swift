import Foundation
import SwiftData

@Model
final class Painting {
    var id: UUID
    var title: String
    var sourceTypeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var width: Int
    var height: Int
    var paletteColorCount: Int

    var projectBlobFilename: String
    var previewFilename: String?

    var completedPixelCount: Int
    var totalPaintablePixelCount: Int
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        sourceType: PaintingSourceType,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        width: Int,
        height: Int,
        paletteColorCount: Int,
        projectBlobFilename: String = "painting.json",
        previewFilename: String? = nil,
        completedPixelCount: Int = 0,
        totalPaintablePixelCount: Int,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceTypeRawValue = sourceType.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.width = width
        self.height = height
        self.paletteColorCount = paletteColorCount
        self.projectBlobFilename = projectBlobFilename
        self.previewFilename = previewFilename
        self.completedPixelCount = completedPixelCount
        self.totalPaintablePixelCount = totalPaintablePixelCount
        self.isCompleted = isCompleted
    }
}

enum PaintingSourceType: String, Codable, Hashable {
    case imported
    case gallery
}
