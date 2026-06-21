import Foundation
import PhraseKit

enum PaintingTitleGenerator {
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
        let generator = PhraseGenerator()
        let phrase = generator.generatePhrase(combinationType: .adjectiveNoun)
            ?? generator.generate(withDefault: "cozy-pixel")
        return titleFromFilename(phrase) ?? "Cozy Pixel"
    }
}
