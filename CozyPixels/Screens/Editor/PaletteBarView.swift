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
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(color.swiftUIColor)
                                .frame(width: 58, height: 42)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selectedPaletteColorID == color.id ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selectedPaletteColorID == color.id ? 4 : 1)
                                }

                            Text("#\(color.id)")
                                .font(.caption.bold())

                            Text("\(completedCountsByColorID[color.id, default: 0])/\(totalCountsByColorID[color.id, default: 0])")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(selectedPaletteColorID == color.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(color.id)")
                }
            }
            .padding(.horizontal)
        }
    }
}

private extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }
}
