import SwiftUI

struct PaletteBarView: View {
    let palette: [PaletteColor]
    @Binding var selectedPaletteColorID: Int?
    var unfinishedColorIDs: Set<Int>

    private var unfinishedPalette: [PaletteColor] {
        palette.filter { unfinishedColorIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(unfinishedPalette) { color in
                    Button {
                        selectedPaletteColorID = color.id
                    } label: {
                        PaletteColorButtonLabel(
                            color: color,
                            isSelected: selectedPaletteColorID == color.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(color.id)")
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct PaletteColorButtonLabel: View {
    let color: PaletteColor
    let isSelected: Bool

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
                Text("\(color.id)")
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
