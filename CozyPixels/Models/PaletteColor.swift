import Foundation

nonisolated struct PaletteColor: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    init(id: Int, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.id = id
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
