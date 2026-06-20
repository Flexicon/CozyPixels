import SwiftData
import SwiftUI

struct GalleryDetailScreen: View {
    let item: GalleryItem

    @Environment(\.modelContext) private var modelContext
    @State private var importResult: ImageImportResult?
    @State private var selectedPaletteColorID: Int?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdPainting: Painting?

    private let store = GalleryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let importResult {
                    PixelCanvasView(state: PixelCanvasRenderState(document: importResult.document, selectedPaletteColorID: selectedPaletteColorID, showGrid: true, showNumbers: true, scale: 1))
                        .frame(maxHeight: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    GalleryAssetImage(assetName: item.assetName)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.largeTitle.bold())
                    Text(item.difficulty.capitalized)
                        .foregroundStyle(.secondary)
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let importResult {
                    paletteSection(importResult)
                    createSection(importResult)
                } else if errorMessage == nil {
                    ProgressView("Loading gallery item...")
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdPainting) { painting in
            PaintingEditorScreen(painting: painting)
        }
        .task {
            loadDocument()
        }
    }

    private func paletteSection(_ result: ImageImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the first correct color")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                ForEach(result.document.palette) { color in
                    Button {
                        selectedPaletteColorID = color.id
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, opacity: Double(color.alpha) / 255))
                                .frame(height: 44)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(selectedPaletteColorID == color.id ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selectedPaletteColorID == color.id ? 3 : 1)
                                }

                            Text("\(color.id)")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func createSection(_ result: ImageImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Opening this preview does not add anything to Home. A gallery painting is created only after your first correct pixel.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(isCreating ? "Creating..." : "Paint First Correct Pixel") {
                Task {
                    await createPainting(from: result)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreating || selectedPaletteColorID == nil)
        }
    }

    private func loadDocument() {
        do {
            let data = try store.data(for: item)
            importResult = try ImageImportService().importImageData(data)
            selectedPaletteColorID = importResult?.document.palette.first?.id
            errorMessage = nil
        } catch {
            errorMessage = "This gallery image could not be loaded."
        }
    }

    @MainActor
    private func createPainting(from result: ImageImportResult) async {
        guard let selectedPaletteColorID else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            var document = result.document
            guard let firstPixelIndex = document.targetColorIndexByPixel.firstIndex(of: UInt16(selectedPaletteColorID)) else {
                errorMessage = "Choose a color that appears in this gallery item."
                return
            }

            var bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)
            bitset.set(firstPixelIndex)
            document.correctPaintedBitset = bitset.data

            let now = Date()
            let painting = Painting(
                title: item.title,
                sourceType: .gallery,
                createdAt: now,
                updatedAt: now,
                width: document.width,
                height: document.height,
                paletteColorCount: document.palette.count,
                previewFilename: PaintingStore.previewFilename,
                completedPixelCount: 1,
                totalPaintablePixelCount: result.paintablePixelCount,
                isCompleted: result.paintablePixelCount == 1
            )

            let paintingStore = try PaintingStore()
            try paintingStore.savePaintingDocument(document, for: painting.id)
            if let previewData = InitialImportPreviewRenderer().pngData(for: document) {
                try paintingStore.savePreviewPNG(previewData, for: painting.id)
            }

            modelContext.insert(painting)
            try modelContext.save()
            createdPainting = painting
        } catch {
            errorMessage = "Could not create this gallery painting. Please try again."
        }
    }
}
