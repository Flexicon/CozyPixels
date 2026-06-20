import Foundation

nonisolated enum PaintPixelResult: Equatable, Sendable {
    case unchanged
    case changed(PaintPixelChange)
}

nonisolated struct PaintPixelChange: Equatable, Sendable {
    var pixelIndex: Int
    var completedDelta: Int
    var previousWrongAttempt: WrongAttempt?
}

nonisolated struct PaintingEngine: Sendable {
    func paintPixel(
        at pixelIndex: Int,
        selectedPaletteColorID: Int,
        in document: inout PaintingDocument
    ) -> PaintPixelResult {
        guard pixelIndex >= 0, pixelIndex < document.targetColorIndexByPixel.count else { return .unchanged }

        let targetColorID = Int(document.targetColorIndexByPixel[pixelIndex])
        guard targetColorID > 0 else { return .unchanged }

        var bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)
        guard !bitset.contains(pixelIndex) else { return .unchanged }

        let previousWrongAttempt = document.wrongAttempts.first { $0.pixelIndex == pixelIndex }

        if selectedPaletteColorID == targetColorID {
            bitset.set(pixelIndex)
            document.correctPaintedBitset = bitset.data
            document.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
            return .changed(PaintPixelChange(pixelIndex: pixelIndex, completedDelta: 1, previousWrongAttempt: previousWrongAttempt))
        }

        if previousWrongAttempt?.attemptedPaletteColorID == selectedPaletteColorID {
            return .unchanged
        }

        document.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
        document.wrongAttempts.append(WrongAttempt(pixelIndex: pixelIndex, attemptedPaletteColorID: selectedPaletteColorID))
        return .changed(PaintPixelChange(pixelIndex: pixelIndex, completedDelta: 0, previousWrongAttempt: previousWrongAttempt))
    }
}
