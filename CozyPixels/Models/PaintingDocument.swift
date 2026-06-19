import Foundation

struct PaintingDocument: Codable, Equatable {
    var version: Int
    var width: Int
    var height: Int
    var palette: [PaletteColor]
    var targetColorIndexByPixel: [UInt16]
    var correctPaintedBitset: Data
    var wrongAttempts: [WrongAttempt]

    init(
        version: Int = 1,
        width: Int,
        height: Int,
        palette: [PaletteColor],
        targetColorIndexByPixel: [UInt16],
        correctPaintedBitset: Data,
        wrongAttempts: [WrongAttempt] = []
    ) {
        self.version = version
        self.width = width
        self.height = height
        self.palette = palette
        self.targetColorIndexByPixel = targetColorIndexByPixel
        self.correctPaintedBitset = correctPaintedBitset
        self.wrongAttempts = wrongAttempts
    }
}

struct WrongAttempt: Codable, Hashable {
    var pixelIndex: Int
    var attemptedPaletteColorID: Int
    var createdAt: Date

    init(pixelIndex: Int, attemptedPaletteColorID: Int, createdAt: Date = Date()) {
        self.pixelIndex = pixelIndex
        self.attemptedPaletteColorID = attemptedPaletteColorID
        self.createdAt = createdAt
    }
}
