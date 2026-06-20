import SwiftUI

struct GalleryScreen: View {
    @State private var items: [GalleryItem] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

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
                            NavigationLink(value: item) {
                                GalleryCardView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Gallery")
        .searchable(text: $searchText, prompt: "Search title or tags")
        .navigationDestination(for: GalleryItem.self) { item in
            GalleryDetailScreen(item: item)
        }
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
