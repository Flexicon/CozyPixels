import SwiftData
import SwiftUI

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Painting.updatedAt, order: .reverse) private var paintings: [Painting]

    @State private var paintingToRename: Painting?
    @State private var renameTitle = ""
    @State private var resetErrorMessage: String?

    private let previewRenderer = PreviewRenderer()

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
                                Button("Rename", systemImage: "pencil") {
                                    beginRename(painting)
                                }

                                Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) {
                                    reset(painting)
                                }

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
        .navigationTitle("Your Creations")
        .alert("Reset Failed", isPresented: resetErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetErrorMessage ?? "This painting could not be reset.")
        }
        .alert("Rename Painting", isPresented: renamePresented) {
            TextField("Name", text: $renameTitle)

            Button("Cancel", role: .cancel) {
                paintingToRename = nil
                renameTitle = ""
            }

            Button("Rename") {
                renamePainting()
            }
        } message: {
            Text("Enter a new name for this painting.")
        }
        .toolbar {
            ImportImageButton()
            #if DEBUG
            if paintings.isEmpty {
                Button("Add Samples") {
                    addSamplePaintings()
                }
            }
            #endif
        }
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

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { paintingToRename != nil },
            set: { isPresented in
                if !isPresented {
                    paintingToRename = nil
                    renameTitle = ""
                }
            }
        )
    }

    private var resetErrorPresented: Binding<Bool> {
        Binding(
            get: { resetErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    resetErrorMessage = nil
                }
            }
        )
    }

    private func reset(_ painting: Painting) {
        do {
            let store = try PaintingStore()
            let document = try store.resetPaintingDocument(for: painting.id)

            painting.completedPixelCount = 0
            painting.isCompleted = false
            painting.updatedAt = Date()

            if let previewData = previewRenderer.pngData(for: document) {
                try store.savePreviewPNG(previewData, for: painting.id)
                painting.previewFilename = PaintingStore.previewFilename
            }

            try modelContext.save()
        } catch {
            resetErrorMessage = "This painting could not be reset."
        }
    }

    private func beginRename(_ painting: Painting) {
        paintingToRename = painting
        renameTitle = painting.title
    }

    private func renamePainting() {
        let trimmedTitle = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let painting = paintingToRename, !trimmedTitle.isEmpty else {
            paintingToRename = nil
            renameTitle = ""
            return
        }

        painting.title = trimmedTitle
        painting.updatedAt = Date()
        try? modelContext.save()

        paintingToRename = nil
        renameTitle = ""
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
