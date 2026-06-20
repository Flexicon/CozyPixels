import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ImportImageButton: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PhotosPickerItem?
    @State private var importResult: ImageImportResult?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var createdPainting: Painting?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .disabled(isImporting)
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await importImage(from: newValue)
            }
        }
        .alert("Import Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The selected image could not be imported.")
        }
        .sheet(item: $importResult) { result in
            ImportReviewScreen(result: result) { title in
                try await createPainting(title: title, from: result)
            }
        }
        .navigationDestination(item: $createdPainting) { painting in
            PaintingEditorScreen(painting: painting)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func importImage(from item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            selectedItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageImportError.unsupportedImageData
            }

            importResult = try ImageImportService().importImageData(data)
        } catch {
            errorMessage = message(for: error)
        }
    }

    @MainActor
    private func createPainting(title: String, from result: ImageImportResult) async throws {
        let now = Date()
        let painting = Painting(
            title: title,
            sourceType: .imported,
            createdAt: now,
            updatedAt: now,
            width: result.document.width,
            height: result.document.height,
            paletteColorCount: result.document.palette.count,
            previewFilename: PaintingStore.previewFilename,
            completedPixelCount: 0,
            totalPaintablePixelCount: result.paintablePixelCount
        )

        let store = try PaintingStore()
        try store.savePaintingDocument(result.document, for: painting.id)
        guard let previewData = PreviewRenderer().pngData(for: result.document) else {
            throw ImportCreationError.previewGenerationFailed
        }
        try store.savePreviewPNG(previewData, for: painting.id)

        modelContext.insert(painting)
        try modelContext.save()
        createdPainting = painting
    }

    private func message(for error: Error) -> String {
        switch error {
        case ImageImportError.unsupportedImageData:
            return "Choose a PNG, JPG, HEIC, or another raster image supported by Photos."
        case ImageImportError.invalidDimensions(let width, let height):
            return "This image has invalid dimensions: \(width) x \(height)."
        case ImageImportError.imageTooLarge(let width, let height, let maximum):
            return "This image is \(width) x \(height). The maximum supported size is \(maximum) x \(maximum)."
        case ImageImportError.tooManyColors(let count, let maximum):
            return "This image has \(count) colors. CozyPixels supports up to \(maximum) exact colors for now."
        default:
            return "The selected image could not be imported. Try a smaller pixel-art PNG or JPG."
        }
    }
}

private enum ImportCreationError: Error {
    case previewGenerationFailed
}

extension ImageImportResult: Identifiable {
    var id: String {
        "\(document.width)x\(document.height)-\(document.palette.count)-\(paintablePixelCount)"
    }
}
