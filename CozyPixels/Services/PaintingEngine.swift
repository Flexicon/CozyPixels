import Foundation

nonisolated enum PaintPixelResult: Equatable, Sendable {
    case unchanged
    case changed(PaintPixelChange)
}

nonisolated enum PaintPixelMode: Equatable, Sendable {
    case allowWrongAttempts
    case correctOnly
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
        mode: PaintPixelMode = .allowWrongAttempts,
        in document: inout PaintingDocument
    ) -> PaintPixelResult {
        guard pixelIndex >= 0, pixelIndex < document.targetColorIndexByPixel.count else { return .unchanged }

        let targetColorID = Int(document.targetColorIndexByPixel[pixelIndex])
        guard targetColorID > 0 else { return .unchanged }

        var bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)
        let wasCorrect = bitset.contains(pixelIndex)

        let previousWrongAttempt = document.wrongAttempts.first { $0.pixelIndex == pixelIndex }

        if selectedPaletteColorID == targetColorID {
            guard !wasCorrect else { return .unchanged }
            bitset.set(pixelIndex)
            document.correctPaintedBitset = bitset.data
            document.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
            return .changed(PaintPixelChange(pixelIndex: pixelIndex, completedDelta: 1, previousWrongAttempt: previousWrongAttempt))
        }

        if !wasCorrect, previousWrongAttempt?.attemptedPaletteColorID == selectedPaletteColorID {
            return .unchanged
        }

        guard mode == .allowWrongAttempts else { return .unchanged }

        if wasCorrect {
            bitset.set(pixelIndex, to: false)
            document.correctPaintedBitset = bitset.data
        }

        document.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
        document.wrongAttempts.append(WrongAttempt(pixelIndex: pixelIndex, attemptedPaletteColorID: selectedPaletteColorID))
        return .changed(PaintPixelChange(pixelIndex: pixelIndex, completedDelta: wasCorrect ? -1 : 0, previousWrongAttempt: previousWrongAttempt))
    }
}
