import Foundation

nonisolated struct Bitset: Equatable, Sendable {
    private(set) var data: Data
    let bitCount: Int

    init(bitCount: Int) {
        precondition(bitCount >= 0, "bitCount must be non-negative")
        self.bitCount = bitCount
        self.data = Data(repeating: 0, count: (bitCount + 7) / 8)
    }

    init(data: Data, bitCount: Int) {
        precondition(bitCount >= 0, "bitCount must be non-negative")
        precondition(data.count >= (bitCount + 7) / 8, "data is too small for bitCount")
        self.data = data
        self.bitCount = bitCount
    }

    func contains(_ index: Int) -> Bool {
        precondition((0..<bitCount).contains(index), "bit index out of bounds")
        let byteIndex = index / 8
        let bitMask = UInt8(1 << (index % 8))
        return data[byteIndex] & bitMask != 0
    }

    mutating func set(_ index: Int, to isSet: Bool = true) {
        precondition((0..<bitCount).contains(index), "bit index out of bounds")
        let byteIndex = index / 8
        let bitMask = UInt8(1 << (index % 8))

        if isSet {
            data[byteIndex] |= bitMask
        } else {
            data[byteIndex] &= ~bitMask
        }
    }
}
