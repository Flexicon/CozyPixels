import Foundation

enum PaintingTitleGenerator {
    private static let adjectives = [
        "Cozy", "Tiny", "Bright", "Calm", "Happy", "Soft", "Sunny", "Quiet"
    ]

    private static let nouns = [
        "Pixel", "Mosaic", "Garden", "Critter", "Sprite", "Pattern", "Canvas", "Puzzle"
    ]

    static func titleFromFilename(_ filename: String) -> String? {
        let name = (filename as NSString).deletingPathExtension
        let cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    static func randomTitle() -> String {
        "\(adjectives.randomElement() ?? "Cozy") \(nouns.randomElement() ?? "Pixel")"
    }
}
