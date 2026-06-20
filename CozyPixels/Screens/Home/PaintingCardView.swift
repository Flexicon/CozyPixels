import SwiftUI

struct PaintingCardView: View {
    let painting: Painting

    @State private var regeneratedPreviewImage: UIImage?

    private var progress: Double {
        guard painting.totalPaintablePixelCount > 0 else { return 0 }
        return Double(painting.completedPixelCount) / Double(painting.totalPaintablePixelCount)
    }

    private var progressText: String {
        progress.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(painting.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(painting.updatedAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .tint(painting.isCompleted ? .green : .accentColor)

                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(painting.title), \(progressText) complete")
    }

    @ViewBuilder
    private var preview: some View {
        if let image = cachedPreviewImage() {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        } else if let regeneratedPreviewImage {
            Image(uiImage: regeneratedPreviewImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        } else {
            PlaceholderPreview(progress: progress, isCompleted: painting.isCompleted)
                .task(id: painting.updatedAt) {
                    regeneratedPreviewImage = await regenerateMissingPreviewImage()
                }
        }
    }

    private func cachedPreviewImage() -> UIImage? {
        guard painting.previewFilename != nil else { return nil }
        guard let store = try? PaintingStore() else { return nil }
        let url = store.previewURL(for: painting.id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func regenerateMissingPreviewImage() async -> UIImage? {
        let paintingID = painting.id

        return await Task.detached(priority: .utility) { () -> UIImage? in
            guard let store = try? PaintingStore() else { return nil }
            guard let document = try? store.loadPaintingDocument(for: paintingID) else { return nil }
            guard let previewData = PreviewRenderer().pngData(for: document) else { return nil }

            try? store.savePreviewPNG(previewData, for: paintingID)
            return UIImage(data: previewData)
        }.value
    }
}

private struct PlaceholderPreview: View {
    let progress: Double
    let isCompleted: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<64, id: \.self) { index in
                Rectangle()
                    .fill(color(for: index))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
    }

    private func color(for index: Int) -> Color {
        let completedCells = Int((progress * 64).rounded(.down))
        guard index < completedCells else {
            return Color.gray.opacity(0.28)
        }

        if isCompleted {
            return Color.green.opacity(0.9)
        }

        let hue = Double(index % 8) / 8.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.9)
    }
}

#Preview {
    PaintingCardView(
        painting: Painting(
            title: "Sample Painting",
            sourceType: .imported,
            width: 32,
            height: 32,
            paletteColorCount: 12,
            completedPixelCount: 420,
            totalPaintablePixelCount: 1_024
        )
    )
    .padding()
}
