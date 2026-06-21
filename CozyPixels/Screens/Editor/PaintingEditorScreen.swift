import SwiftData
import SwiftUI

struct PaintingEditorScreen: View {
    let painting: Painting

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var document: PaintingDocument?
    @State private var renderCache: PixelCanvasRenderCache?
    @State private var pixelImage: CGImage?
    @State private var unfinishedColorIDs = Set<Int>()
    @State private var selectedPaletteColorID: Int?
    @State private var showGrid = true
    @State private var showNumbers = true
    @State private var canvasResetToken = 0
    @State private var strokeDidChange = false
    @State private var activeStrokePaletteColorID: Int?
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var previewSaveTask: Task<Void, Never>?
    @State private var isLoadingDocument = false

    private let store = try? PaintingStore()
    private let previewRenderer = PreviewRenderer()
    private let pixelImageRenderer = PixelCanvasImageRenderer()
    private let paintingEngine = PaintingEngine()
    private let editorBackground = Color(red: 0.11, green: 0.11, blue: 0.11)

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if let document, let renderCache {
                        InteractivePixelCanvas(
                            document: document,
                            renderCache: renderCache,
                            pixelImage: pixelImage,
                            selectedPaletteColorID: selectedPaletteColorID,
                            showGrid: showGrid,
                            showNumbers: showNumbers,
                            resetToken: canvasResetToken,
                            onTapPixel: { pixelIndex in
                                paint(pixelIndex: pixelIndex, document: document, mode: .allowWrongAttempts, updatePreview: true)
                            },
                            onStrokePixel: { pixelIndex, phase in
                                handlePaintStroke(pixelIndex: pixelIndex, phase: phase)
                            }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    } else if let errorMessage {
                        ContentUnavailableView("Editor Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    } else {
                        ProgressView("Loading painting...")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Back")
                    .padding(.leading, 16)
                    .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(editorBackground)
                .ignoresSafeArea(edges: .top)
            }

            if let saveErrorMessage {
                Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }

            Rectangle()
                .fill(editorBackground)
                .frame(height: 1)

            if let document {
                PaletteBarView(
                    palette: document.palette,
                    selectedPaletteColorID: $selectedPaletteColorID,
                    unfinishedColorIDs: unfinishedColorIDs
                )
                .padding(.vertical, 10)
            }
        }
        .background(editorBackground)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .task {
            loadDocument()
        }
        .onDisappear {
            if strokeDidChange {
                persistDocument(updatePreview: true)
                strokeDidChange = false
            }
        }
        .onChange(of: selectedPaletteColorID) { _, _ in
            guard !isLoadingDocument else { return }
            persistSelectedPaletteColorID()
            rebuildPixelImage()
        }
    }

    private func handlePaintStroke(pixelIndex: Int, phase: CanvasInputPhase) {
        switch phase {
        case .began:
            strokeDidChange = false
            activeStrokePaletteColorID = selectedPaletteColorID
        case .changed:
            guard let document else { return }
            paint(pixelIndex: pixelIndex, document: document, mode: .correctOnly, updatePreview: false)
        case .ended:
            if strokeDidChange {
                persistDocument(updatePreview: true)
            }
            strokeDidChange = false
            activeStrokePaletteColorID = nil
        case .cancelled:
            if strokeDidChange {
                persistDocument(updatePreview: true)
            }
            strokeDidChange = false
            activeStrokePaletteColorID = nil
        }
    }

    private func loadDocument() {
        do {
            isLoadingDocument = true
            defer { isLoadingDocument = false }
            guard let store else { throw PaintingStoreError.missingPaintingDocument(URL(filePath: painting.projectBlobFilename)) }
            let loadedDocument = try store.loadPaintingDocument(for: painting.id)
            let loadedCache = PixelCanvasRenderCache(document: loadedDocument)
            document = loadedDocument
            renderCache = loadedCache
            unfinishedColorIDs = makeUnfinishedColorIDs(for: loadedDocument)
            updateSelectedPaletteColorID(for: loadedDocument, preferredColorID: loadedDocument.lastSelectedPaletteColorID)
            pixelImage = pixelImageRenderer.makeImage(document: loadedDocument, cache: loadedCache, selectedPaletteColorID: selectedPaletteColorID)
            errorMessage = nil
        } catch PaintingStoreError.missingPaintingDocument {
            errorMessage = "This painting file is missing. Delete it from Your Creations or restore it from a backup."
        } catch PaintingStoreError.corruptPaintingDocument {
            errorMessage = "This painting file is corrupt and cannot be opened."
        } catch {
            errorMessage = "This painting could not be loaded."
        }
    }

    private func paint(pixelIndex: Int, document currentDocument: PaintingDocument, mode: PaintPixelMode, updatePreview: Bool) {
        guard let selectedPaletteColorID = activeStrokePaletteColorID ?? selectedPaletteColorID else { return }
        guard pixelIndex < currentDocument.targetColorIndexByPixel.count else { return }

        var updatedDocument = currentDocument
        let result = paintingEngine.paintPixel(at: pixelIndex, selectedPaletteColorID: selectedPaletteColorID, mode: mode, in: &updatedDocument)
        guard case .changed(let change) = result else { return }

        let wasCompleted = painting.isCompleted
        painting.completedPixelCount += change.completedDelta

        painting.updatedAt = Date()
        painting.isCompleted = painting.completedPixelCount >= painting.totalPaintablePixelCount
        let updatedCache = PixelCanvasRenderCache(document: updatedDocument)
        document = updatedDocument
        renderCache = updatedCache
        unfinishedColorIDs = makeUnfinishedColorIDs(for: updatedDocument)

        if !wasCompleted, painting.isCompleted {
            canvasResetToken += 1
            showGrid = false
        }
        updateSelectedPaletteColorID(for: updatedDocument, preferredColorID: selectedPaletteColorID)
        updatedDocument.lastSelectedPaletteColorID = selectedPaletteColorID
        document = updatedDocument
        pixelImage = pixelImageRenderer.makeImage(document: updatedDocument, cache: updatedCache, selectedPaletteColorID: selectedPaletteColorID)

        if updatePreview {
            persistDocument(updatePreview: true)
        } else {
            strokeDidChange = true
        }
    }

    private func updateSelectedPaletteColorID(for document: PaintingDocument, preferredColorID: Int?) {
        let remainingColorIDs = remainingColorIDs(for: document.palette)
        if let preferredColorID, remainingColorIDs.contains(preferredColorID) {
            selectedPaletteColorID = preferredColorID
            return
        }
        selectedPaletteColorID = remainingColorIDs.first
    }

    private func rebuildPixelImage() {
        guard let document, let renderCache else { return }
        pixelImage = pixelImageRenderer.makeImage(document: document, cache: renderCache, selectedPaletteColorID: selectedPaletteColorID)
    }

    private func persistDocument(updatePreview: Bool = false) {
        guard let document else { return }
        guard let store else {
            saveErrorMessage = "Painting storage is unavailable. Your latest change could not be saved."
            return
        }

        do {
            try store.savePaintingDocument(document, for: painting.id)
            if updatePreview {
                painting.previewFilename = PaintingStore.previewFilename
                let paintingID = painting.id
                let previewRenderer = previewRenderer
                previewSaveTask?.cancel()
                previewSaveTask = Task.detached(priority: .utility) {
                    guard let previewData = previewRenderer.pngData(for: document), !Task.isCancelled else { return }
                    guard let previewStore = try? PaintingStore() else { return }
                    try? previewStore.savePreviewPNG(previewData, for: paintingID)
                }
            }
            try modelContext.save()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Your latest change could not be saved."
        }
    }

    private func persistSelectedPaletteColorID() {
        guard var updatedDocument = document else { return }
        guard updatedDocument.lastSelectedPaletteColorID != selectedPaletteColorID else { return }

        updatedDocument.lastSelectedPaletteColorID = selectedPaletteColorID
        document = updatedDocument
        persistDocument()
    }

    private func makeUnfinishedColorIDs(for document: PaintingDocument) -> Set<Int> {
        let bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)

        return document.targetColorIndexByPixel.enumerated().reduce(into: Set<Int>()) { colorIDs, item in
            guard !bitset.contains(item.offset) else { return }
            let colorID = Int(item.element)
            guard colorID > 0 else { return }
            colorIDs.insert(colorID)
        }
    }

    private func remainingColorIDs(for palette: [PaletteColor]) -> [Int] {
        palette.compactMap { color in
            unfinishedColorIDs.contains(color.id) ? color.id : nil
        }
    }
}
