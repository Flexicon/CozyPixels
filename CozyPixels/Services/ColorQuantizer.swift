import Foundation

nonisolated struct ColorQuantizer: Sendable {
    private static let similarColorDistanceSquared = 28 * 28

    func quantize(_ pixels: [RGBAPixel], maxColors: Int) -> [RGBAPixel] {
        guard maxColors > 0 else {
            return pixels.map { $0.alpha == 0 ? $0 : RGBAPixel(red: 0, green: 0, blue: 0, alpha: $0.alpha) }
        }

        let paintableColors = Set(pixels.filter { $0.alpha != 0 })
        let mergedPixels = mergeSimilarColors(in: pixels, colors: paintableColors)
        let mergedPaintableColors = Set(mergedPixels.filter { $0.alpha != 0 })
        guard mergedPaintableColors.count > maxColors else { return mergedPixels }

        var boxes = [ColorBox(colors: Array(mergedPaintableColors))]
        while boxes.count < maxColors {
            guard let splitIndex = boxes.indices.max(by: { boxes[$0].splitPriority < boxes[$1].splitPriority }),
                  boxes[splitIndex].colors.count > 1 else {
                break
            }

            let box = boxes.remove(at: splitIndex)
            let split = box.split()
            boxes.append(split.left)
            boxes.append(split.right)
        }

        let representatives = boxes.map { $0.representative }
        var colorMap = [RGBAPixel: RGBAPixel](minimumCapacity: mergedPaintableColors.count)
        for color in mergedPaintableColors {
            colorMap[color] = representatives.min { lhs, rhs in
                distanceSquared(from: color, to: lhs) < distanceSquared(from: color, to: rhs)
            }
        }

        return mergedPixels.map { pixel in
            guard pixel.alpha != 0 else { return pixel }
            return colorMap[pixel] ?? pixel
        }
    }

    private func mergeSimilarColors(in pixels: [RGBAPixel], colors: Set<RGBAPixel>) -> [RGBAPixel] {
        let groups = similarColorGroups(for: colors)
        guard groups.count < colors.count else { return pixels }

        var colorMap = [RGBAPixel: RGBAPixel](minimumCapacity: colors.count)
        for group in groups {
            let representative = ColorBox(colors: group).representative
            for color in group {
                colorMap[color] = representative
            }
        }

        return pixels.map { pixel in
            guard pixel.alpha != 0 else { return pixel }
            return colorMap[pixel] ?? pixel
        }
    }

    private func similarColorGroups(for colors: Set<RGBAPixel>) -> [[RGBAPixel]] {
        var groups = [[RGBAPixel]]()
        for color in colors.sorted(by: sortsBefore) {
            if let index = groups.firstIndex(where: { group in
                distanceSquared(from: color, to: ColorBox(colors: group).representative) <= Self.similarColorDistanceSquared
            }) {
                groups[index].append(color)
            } else {
                groups.append([color])
            }
        }
        return groups
    }

    private func distanceSquared(from lhs: RGBAPixel, to rhs: RGBAPixel) -> Int {
        let red = Int(lhs.red) - Int(rhs.red)
        let green = Int(lhs.green) - Int(rhs.green)
        let blue = Int(lhs.blue) - Int(rhs.blue)
        let alpha = Int(lhs.alpha) - Int(rhs.alpha)
        return red * red + green * green + blue * blue + alpha * alpha
    }

    private func sortsBefore(_ lhs: RGBAPixel, _ rhs: RGBAPixel) -> Bool {
        if lhs.red != rhs.red { return lhs.red < rhs.red }
        if lhs.green != rhs.green { return lhs.green < rhs.green }
        if lhs.blue != rhs.blue { return lhs.blue < rhs.blue }
        return lhs.alpha < rhs.alpha
    }
}

nonisolated private struct ColorBox {
    var colors: [RGBAPixel]

    var splitPriority: (range: UInt8, count: Int) {
        (max(channelRange(\.red), channelRange(\.green), channelRange(\.blue), channelRange(\.alpha)), colors.count)
    }

    var representative: RGBAPixel {
        let count = colors.count
        let sums = colors.reduce(into: (red: 0, green: 0, blue: 0, alpha: 0)) { result, color in
            result.red += Int(color.red)
            result.green += Int(color.green)
            result.blue += Int(color.blue)
            result.alpha += Int(color.alpha)
        }

        return RGBAPixel(
            red: UInt8(sums.red / count),
            green: UInt8(sums.green / count),
            blue: UInt8(sums.blue / count),
            alpha: UInt8(sums.alpha / count)
        )
    }

    func split() -> (left: ColorBox, right: ColorBox) {
        let keyPath = widestChannel
        let sortedColors = colors.sorted { lhs, rhs in
            if lhs[keyPath: keyPath] != rhs[keyPath: keyPath] { return lhs[keyPath: keyPath] < rhs[keyPath: keyPath] }
            if lhs.red != rhs.red { return lhs.red < rhs.red }
            if lhs.green != rhs.green { return lhs.green < rhs.green }
            if lhs.blue != rhs.blue { return lhs.blue < rhs.blue }
            return lhs.alpha < rhs.alpha
        }
        let midpoint = sortedColors.count / 2
        return (
            ColorBox(colors: Array(sortedColors[..<midpoint])),
            ColorBox(colors: Array(sortedColors[midpoint...]))
        )
    }

    private var widestChannel: KeyPath<RGBAPixel, UInt8> {
        let ranges: [(KeyPath<RGBAPixel, UInt8>, UInt8)] = [
            (\.red, channelRange(\.red)),
            (\.green, channelRange(\.green)),
            (\.blue, channelRange(\.blue)),
            (\.alpha, channelRange(\.alpha))
        ]
        return ranges.max { $0.1 < $1.1 }?.0 ?? \.red
    }

    private func channelRange(_ keyPath: KeyPath<RGBAPixel, UInt8>) -> UInt8 {
        let values = colors.map { $0[keyPath: keyPath] }
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }
}
