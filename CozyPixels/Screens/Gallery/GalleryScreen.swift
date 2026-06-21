import SwiftData
import SwiftUI

struct GalleryScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var items: [GalleryItem] = []
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

    let onOpenPainting: (Painting) -> Void

    private let store = GalleryStore()
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 16)]

    private var filteredItems: [GalleryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }

        return items.filter { item in
            item.title.lowercased().contains(query) || item.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("Gallery Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Gallery Items" : "No Results",
                    systemImage: "photo.on.rectangle",
                    description: Text(searchText.isEmpty ? "Bundled examples will appear here." : "Try searching by title or tag.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredItems) { item in
                            Button {
                                Task {
                                    await createAndOpenPainting(from: item)
                                }
                            } label: {
                                GalleryCardView(item: item)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCreating)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Gallery")
        .searchable(text: $searchText, prompt: "Search title or tags")
        .task {
            loadItems()
        }
    }

    private func loadItems() {
        do {
            items = try store.loadItems()
            errorMessage = nil
        } catch GalleryStoreError.missingManifest {
            errorMessage = "The bundled gallery manifest is missing. Reinstall or update the app."
        } catch GalleryStoreError.corruptManifest {
            errorMessage = "The bundled gallery manifest is corrupt. Reinstall or update the app."
        } catch {
            errorMessage = "Bundled gallery examples could not be loaded."
        }
    }

    @MainActor
    private func createAndOpenPainting(from item: GalleryItem) async {
        isCreating = true
        defer { isCreating = false }

        do {
            let data = try store.data(for: item)
            let result = try ImageImportService().importTrustedImageData(data)
            let now = Date()
            let painting = Painting(
                title: item.title,
                sourceType: .gallery,
                createdAt: now,
                updatedAt: now,
                width: result.document.width,
                height: result.document.height,
                paletteColorCount: result.document.palette.count,
                previewFilename: PaintingStore.previewFilename,
                completedPixelCount: 0,
                totalPaintablePixelCount: result.paintablePixelCount
            )

            let paintingStore = try PaintingStore()
            try paintingStore.savePaintingDocument(result.document, for: painting.id)
            guard let previewData = PreviewRenderer().pngData(for: result.document) else {
                throw GalleryCreationError.previewGenerationFailed
            }
            try paintingStore.savePreviewPNG(previewData, for: painting.id)

            modelContext.insert(painting)
            try modelContext.save()
            onOpenPainting(painting)
        } catch GalleryStoreError.missingAsset(let assetName) {
            errorMessage = "The gallery asset \"\(assetName)\" is missing."
        } catch {
            errorMessage = "This gallery image could not be loaded."
        }
    }
}

private enum GalleryCreationError: Error {
    case previewGenerationFailed
}

private struct GalleryCardView: View {
    let item: GalleryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GalleryAssetImage(assetName: item.assetName)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.difficulty.capitalized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

struct GalleryAssetImage: View {
    let assetName: String

    var body: some View {
        if let url = GalleryStore().resourceURL(for: assetName, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .saturation(0)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 38))
                Text("Missing Asset")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }
}
