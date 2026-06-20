import SwiftUI

struct PaletteBarView: View {
    let palette: [PaletteColor]
    @Binding var selectedPaletteColorID: Int?
    var completedCountsByColorID: [Int: Int]
    var totalCountsByColorID: [Int: Int]

    private var remainingPalette: [(color: PaletteColor, remainingCount: Int)] {
        palette.compactMap { color in
            let remainingCount = totalCountsByColorID[color.id, default: 0] - completedCountsByColorID[color.id, default: 0]
            guard remainingCount > 0 else { return nil }
            return (color, remainingCount)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(remainingPalette, id: \.color.id) { item in
                    Button {
                        selectedPaletteColorID = item.color.id
                    } label: {
                        PaletteColorButtonLabel(
                            color: item.color,
                            isSelected: selectedPaletteColorID == item.color.id,
                            remainingCount: item.remainingCount
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(item.color.id), \(item.remainingCount) pixels remaining")
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct PaletteColorButtonLabel: View {
    let color: PaletteColor
    let isSelected: Bool
    let remainingCount: Int

    var body: some View {
        swatch
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.swiftUIColor)
            .frame(width: 58, height: 42)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 4 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.white, Color.accentColor)
                        .padding(4)
                }
            }
            .overlay {
                Text("\(remainingCount)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
            }
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
