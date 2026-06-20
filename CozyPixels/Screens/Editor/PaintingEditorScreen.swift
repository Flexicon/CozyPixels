import SwiftData
import SwiftUI

struct PaintingEditorScreen: View {
    let painting: Painting

    @Environment(\.modelContext) private var modelContext
    @State private var document: PaintingDocument?
    @State private var selectedPaletteColorID: Int?
    @State private var showGrid = true
    @State private var showNumbers = true
    @State private var transform = CanvasTransform()
    @State private var gestureStartTransform = CanvasTransform()
    @State private var hasCurrentStrokeChanges = false
    @State private var processedPixelsInStroke: Set<Int> = []
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var previewSaveTask: Task<Void, Never>?

    private let store = try? PaintingStore()
    private let previewRenderer = PreviewRenderer()
    private let paintingEngine = PaintingEngine()
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    if let document {
                        PixelCanvasView(
                            state: PixelCanvasRenderState(
                                document: document,
                                selectedPaletteColorID: selectedPaletteColorID,
                                showGrid: showGrid,
                                showNumbers: showNumbers,
                                scale: transform.scale
                            ),
                            transform: transform
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .gesture(canvasGesture(canvasSize: proxy.size, document: document))
                    } else if let errorMessage {
                        ContentUnavailableView("Editor Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    } else {
                        ProgressView("Loading painting...")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
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

            Divider()

            if let document {
                PaletteBarView(
                    palette: document.palette,
                    selectedPaletteColorID: $selectedPaletteColorID,
                    completedCountsByColorID: completedCountsByColorID(for: document),
                    totalCountsByColorID: totalCountsByColorID(for: document)
                )
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(painting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            loadDocument()
        }
        .onDisappear {
            previewSaveTask?.cancel()
        }
    }

    private func canvasGesture(canvasSize: CGSize, document: PaintingDocument) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    transform.scale = min(max(gestureStartTransform.scale * value.magnification, minScale), maxScale)
                }
                .onEnded { _ in
                    gestureStartTransform = transform
                },
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if selectedPaletteColorID == nil {
                        transform.offset = CGSize(
                            width: gestureStartTransform.offset.width + value.translation.width,
                            height: gestureStartTransform.offset.height + value.translation.height
                        )
                    } else {
                        paint(at: value.location, canvasSize: canvasSize, document: document)
                    }
                }
                .onEnded { _ in
                    if hasCurrentStrokeChanges {
                        persistDocument(updatePreview: true)
                    }
                    hasCurrentStrokeChanges = false
                    processedPixelsInStroke.removeAll()
                    gestureStartTransform = transform
                }
        )
    }

    private func loadDocument() {
        do {
            guard let store else { throw PaintingStoreError.missingPaintingDocument(URL(filePath: painting.projectBlobFilename)) }
            let loadedDocument = try store.loadPaintingDocument(for: painting.id)
            document = loadedDocument
            selectedPaletteColorID = selectedPaletteColorID ?? loadedDocument.palette.first?.id
            errorMessage = nil
        } catch PaintingStoreError.missingPaintingDocument {
            errorMessage = "This painting file is missing. Delete it from Home or restore it from a backup."
        } catch PaintingStoreError.corruptPaintingDocument {
            errorMessage = "This painting file is corrupt and cannot be opened."
        } catch {
            errorMessage = "This painting could not be loaded."
        }
    }

    private func paint(at point: CGPoint, canvasSize: CGSize, document currentDocument: PaintingDocument) {
        guard let selectedPaletteColorID else { return }
        let imageSize = PixelSize(width: currentDocument.width, height: currentDocument.height)
        guard let coordinate = transform.screenPointToPixel(point, canvasSize: canvasSize, imageSize: imageSize) else { return }

        let pixelIndex = coordinate.pixelIndex(in: imageSize)
        guard !processedPixelsInStroke.contains(pixelIndex), pixelIndex < currentDocument.targetColorIndexByPixel.count else { return }
        processedPixelsInStroke.insert(pixelIndex)

        var updatedDocument = currentDocument
        let result = paintingEngine.paintPixel(at: pixelIndex, selectedPaletteColorID: selectedPaletteColorID, in: &updatedDocument)
        guard case .changed(let change) = result else { return }

        painting.completedPixelCount += change.completedDelta

        painting.updatedAt = Date()
        painting.isCompleted = painting.completedPixelCount >= painting.totalPaintablePixelCount
        document = updatedDocument

        hasCurrentStrokeChanges = true
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

    private func totalCountsByColorID(for document: PaintingDocument) -> [Int: Int] {
        document.targetColorIndexByPixel.reduce(into: [:]) { counts, colorID in
            let colorID = Int(colorID)
            guard colorID > 0 else { return }
            counts[colorID, default: 0] += 1
        }
    }

    private func completedCountsByColorID(for document: PaintingDocument) -> [Int: Int] {
        let bitset = Bitset(data: document.correctPaintedBitset, bitCount: document.width * document.height)

        return document.targetColorIndexByPixel.enumerated().reduce(into: [:]) { counts, item in
            guard bitset.contains(item.offset) else { return }
            let colorID = Int(item.element)
            guard colorID > 0 else { return }
            counts[colorID, default: 0] += 1
        }
    }
}
