import SwiftData
import SwiftUI

struct PaintingEditorScreen: View {
    let painting: Painting

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var document: PaintingDocument?
    @State private var selectedPaletteColorID: Int?
    @State private var showGrid = false
    @State private var showNumbers = true
    @State private var transform = CanvasTransform()
    @State private var gestureStartTransform = CanvasTransform()
    @State private var pinchStartLocation: CGPoint?
    @State private var lastStrokePixelIndex: Int?
    @State private var strokeDidChange = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var previewSaveTask: Task<Void, Never>?

    private let store = try? PaintingStore()
    private let previewRenderer = PreviewRenderer()
    private let paintingEngine = PaintingEngine()
    private let editorBackground = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
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

                        CanvasInputOverlay(
                            onTap: { point in
                                paint(at: point, canvasSize: proxy.size, document: document, updatePreview: true)
                            },
                            onPan: { translation, phase in
                                handlePan(translation: translation, phase: phase)
                            },
                            onPinch: { magnification, location, phase in
                                handlePinch(magnification: magnification, location: location, phase: phase, canvasSize: proxy.size, document: document)
                            },
                            onPaintStroke: { point, phase in
                                handlePaintStroke(at: point, phase: phase, canvasSize: proxy.size, document: document)
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
                    .padding(.top, max(proxy.safeAreaInsets.top, 12))
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
                    completedCountsByColorID: completedCountsByColorID(for: document),
                    totalCountsByColorID: totalCountsByColorID(for: document)
                )
                .padding(.vertical, 10)
            }
        }
        .background(editorBackground)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            loadDocument()
        }
        .onDisappear {
            previewSaveTask?.cancel()
        }
    }

    private func handlePan(translation: CGSize, phase: CanvasInputPhase) {
        switch phase {
        case .began:
            gestureStartTransform = transform
        case .changed:
            transform.offset = CGSize(
                width: gestureStartTransform.offset.width + translation.width,
                height: gestureStartTransform.offset.height + translation.height
            )
        case .ended, .cancelled:
            gestureStartTransform = transform
        }
    }

    private func handlePinch(magnification: CGFloat, location: CGPoint, phase: CanvasInputPhase, canvasSize: CGSize, document: PaintingDocument) {
        let imageSize = PixelSize(width: document.width, height: document.height)

        switch phase {
        case .began:
            gestureStartTransform = transform
            pinchStartLocation = location
        case .changed:
            let anchorLocation = pinchStartLocation ?? location
            let previousGeometry = gestureStartTransform.geometry(canvasSize: canvasSize, imageSize: imageSize)
            let newScale = min(max(gestureStartTransform.scale * magnification, minScale), maxScale)
            var nextTransform = CanvasTransform(scale: newScale, offset: gestureStartTransform.offset)
            let nextGeometry = nextTransform.geometry(canvasSize: canvasSize, imageSize: imageSize)
            guard previousGeometry.cellSize > 0, nextGeometry.cellSize > 0 else {
                transform = nextTransform
                return
            }

            let localX = (anchorLocation.x - previousGeometry.origin.x) / previousGeometry.cellSize
            let localY = (anchorLocation.y - previousGeometry.origin.y) / previousGeometry.cellSize
            let nextOrigin = nextGeometry.origin
            nextTransform.offset = CGSize(
                width: nextTransform.offset.width + anchorLocation.x - (nextOrigin.x + localX * nextGeometry.cellSize),
                height: nextTransform.offset.height + anchorLocation.y - (nextOrigin.y + localY * nextGeometry.cellSize)
            )
            transform = nextTransform
        case .ended, .cancelled:
            gestureStartTransform = transform
            pinchStartLocation = nil
        }
    }

    private func handlePaintStroke(at point: CGPoint, phase: CanvasInputPhase, canvasSize: CGSize, document: PaintingDocument) {
        switch phase {
        case .began:
            lastStrokePixelIndex = nil
            strokeDidChange = false
        case .changed:
            paint(at: point, canvasSize: canvasSize, document: document, updatePreview: false)
        case .ended:
            if strokeDidChange {
                persistDocument(updatePreview: true)
            }
            lastStrokePixelIndex = nil
            strokeDidChange = false
        case .cancelled:
            if strokeDidChange {
                persistDocument(updatePreview: true)
            }
            lastStrokePixelIndex = nil
            strokeDidChange = false
        }
    }

    private func loadDocument() {
        do {
            guard let store else { throw PaintingStoreError.missingPaintingDocument(URL(filePath: painting.projectBlobFilename)) }
            let loadedDocument = try store.loadPaintingDocument(for: painting.id)
            document = loadedDocument
            updateSelectedPaletteColorID(for: loadedDocument)
            errorMessage = nil
        } catch PaintingStoreError.missingPaintingDocument {
            errorMessage = "This painting file is missing. Delete it from Home or restore it from a backup."
        } catch PaintingStoreError.corruptPaintingDocument {
            errorMessage = "This painting file is corrupt and cannot be opened."
        } catch {
            errorMessage = "This painting could not be loaded."
        }
    }

    private func paint(at point: CGPoint, canvasSize: CGSize, document currentDocument: PaintingDocument, updatePreview: Bool) {
        guard let selectedPaletteColorID else { return }
        let imageSize = PixelSize(width: currentDocument.width, height: currentDocument.height)
        guard let coordinate = transform.screenPointToPixel(point, canvasSize: canvasSize, imageSize: imageSize) else { return }

        let pixelIndex = coordinate.pixelIndex(in: imageSize)
        guard pixelIndex < currentDocument.targetColorIndexByPixel.count else { return }
        guard lastStrokePixelIndex != pixelIndex || updatePreview else { return }
        lastStrokePixelIndex = pixelIndex

        var updatedDocument = currentDocument
        let result = paintingEngine.paintPixel(at: pixelIndex, selectedPaletteColorID: selectedPaletteColorID, in: &updatedDocument)
        guard case .changed(let change) = result else { return }

        let wasCompleted = painting.isCompleted
        painting.completedPixelCount += change.completedDelta

        painting.updatedAt = Date()
        painting.isCompleted = painting.completedPixelCount >= painting.totalPaintablePixelCount
        document = updatedDocument

        if !wasCompleted, painting.isCompleted {
            transform = CanvasTransform()
            gestureStartTransform = transform
            showGrid = false
        }
        updateSelectedPaletteColorID(for: updatedDocument)

        if updatePreview {
            persistDocument(updatePreview: true)
        } else {
            strokeDidChange = true
            persistDocument()
        }
    }

    private func updateSelectedPaletteColorID(for document: PaintingDocument) {
        let remainingColorIDs = remainingColorIDs(for: document)
        if let selectedPaletteColorID, remainingColorIDs.contains(selectedPaletteColorID) {
            return
        }
        selectedPaletteColorID = remainingColorIDs.first
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

    private func remainingColorIDs(for document: PaintingDocument) -> [Int] {
        let completedCounts = completedCountsByColorID(for: document)
        let totalCounts = totalCountsByColorID(for: document)

        return document.palette.compactMap { color in
            let remainingCount = totalCounts[color.id, default: 0] - completedCounts[color.id, default: 0]
            return remainingCount > 0 ? color.id : nil
        }
    }
}
