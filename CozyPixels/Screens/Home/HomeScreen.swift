import SwiftData
import SwiftUI

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Painting.updatedAt, order: .reverse) private var paintings: [Painting]

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 16)
    ]

    var body: some View {
        Group {
            if paintings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(paintings) { painting in
                            NavigationLink(value: painting) {
                                PaintingCardView(painting: painting)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(painting)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Home")
        .navigationDestination(for: Painting.self) { painting in
            PaintingEditorPlaceholderView(painting: painting)
        }
        #if DEBUG
        .toolbar {
            if paintings.isEmpty {
                Button("Add Samples") {
                    addSamplePaintings()
                }
            }
        }
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Paintings Yet", systemImage: "paintpalette")
        } description: {
            Text("Import a pixel art image or open Gallery to start painting.")
        }
    }

    private func delete(_ painting: Painting) {
        if let store = try? PaintingStore() {
            try? store.deletePaintingDirectory(for: painting.id)
        }

        modelContext.delete(painting)
    }

    #if DEBUG
    private func addSamplePaintings() {
        let now = Date()
        let samples = [
            Painting(
                title: "Tiny Apple",
                sourceType: .imported,
                createdAt: now.addingTimeInterval(-8_000),
                updatedAt: now.addingTimeInterval(-600),
                width: 16,
                height: 16,
                paletteColorCount: 8,
                previewFilename: nil,
                completedPixelCount: 64,
                totalPaintablePixelCount: 256
            ),
            Painting(
                title: "Cozy Mug",
                sourceType: .gallery,
                createdAt: now.addingTimeInterval(-20_000),
                updatedAt: now.addingTimeInterval(-3_600),
                width: 32,
                height: 32,
                paletteColorCount: 12,
                previewFilename: nil,
                completedPixelCount: 512,
                totalPaintablePixelCount: 1_024
            ),
            Painting(
                title: "Moon Cat",
                sourceType: .imported,
                createdAt: now.addingTimeInterval(-40_000),
                updatedAt: now.addingTimeInterval(-12_000),
                width: 64,
                height: 64,
                paletteColorCount: 20,
                previewFilename: nil,
                completedPixelCount: 4_096,
                totalPaintablePixelCount: 4_096,
                isCompleted: true
            )
        ]

        for sample in samples {
            modelContext.insert(sample)
        }
    }
    #endif
}

private struct PaintingEditorPlaceholderView: View {
    let painting: Painting

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text(painting.title)
                .font(.title2.bold())

            Text("Editor arrives in Phase 8.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Editor")
        .navigationBarTitleDisplayMode(.inline)
    }
}
