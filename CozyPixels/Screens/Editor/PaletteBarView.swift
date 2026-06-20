import SwiftUI

struct PaletteBarView: View {
    let palette: [PaletteColor]
    @Binding var selectedPaletteColorID: Int?
    var completedCountsByColorID: [Int: Int]
    var totalCountsByColorID: [Int: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(palette) { color in
                    Button {
                        selectedPaletteColorID = color.id
                    } label: {
                        PaletteColorButtonLabel(
                            color: color,
                            isSelected: selectedPaletteColorID == color.id,
                            completedCount: completedCountsByColorID[color.id, default: 0],
                            totalCount: totalCountsByColorID[color.id, default: 0]
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
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(spacing: 6) {
            swatch

            Text("#\(color.id)")
                .font(.callout.bold())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)

            Text("\(completedCount)/\(totalCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
