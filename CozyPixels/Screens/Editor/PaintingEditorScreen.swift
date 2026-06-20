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
    @State private var currentStroke: StrokeChange?
    @State private var processedPixelsInStroke: Set<Int> = []
    @State private var strokeHistory: [StrokeChange] = []
    @State private var errorMessage: String?
    @State private var resetConfirmationPresented = false

    private let store = try? PaintingStore()
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                title: painting.title,
                progressText: progressText,
                showGrid: $showGrid,
                showNumbers: $showNumbers,
                canUndo: !strokeHistory.isEmpty,
                undoAction: undoLastStroke,
                resetAction: { resetConfirmationPresented = true }
            )
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

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
        .confirmationDialog("Reset this painting?", isPresented: $resetConfirmationPresented, titleVisibility: .visible) {
            Button("Reset Painting", role: .destructive) {
                resetPainting()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears completed pixels and wrong attempts for this painting.")
        }
    }

    private var progressText: String {
        guard painting.totalPaintablePixelCount > 0 else { return "0%" }
        let percentage = Double(painting.completedPixelCount) / Double(painting.totalPaintablePixelCount)
        return percentage.formatted(.percent.precision(.fractionLength(0)))
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
                    if let currentStroke, !currentStroke.changes.isEmpty {
                        strokeHistory.append(currentStroke)
                        persistDocument()
                    }
                    currentStroke = nil
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

        let targetColorID = Int(currentDocument.targetColorIndexByPixel[pixelIndex])
        guard targetColorID > 0 else { return }

        var updatedDocument = currentDocument
        var bitset = Bitset(data: updatedDocument.correctPaintedBitset, bitCount: updatedDocument.width * updatedDocument.height)
        guard !bitset.contains(pixelIndex) else { return }

        let previousWrongAttempt = updatedDocument.wrongAttempts.first { $0.pixelIndex == pixelIndex }

        if selectedPaletteColorID == targetColorID {
            bitset.set(pixelIndex)
            updatedDocument.correctPaintedBitset = bitset.data
            updatedDocument.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
            painting.completedPixelCount += 1
        } else {
            if previousWrongAttempt?.attemptedPaletteColorID == selectedPaletteColorID {
                return
            }

            updatedDocument.wrongAttempts.removeAll { $0.pixelIndex == pixelIndex }
            updatedDocument.wrongAttempts.append(WrongAttempt(pixelIndex: pixelIndex, attemptedPaletteColorID: selectedPaletteColorID))
        }

        painting.updatedAt = Date()
        painting.isCompleted = painting.completedPixelCount >= painting.totalPaintablePixelCount
        document = updatedDocument

        let pixelChange = PixelChange(pixelIndex: pixelIndex, previousWrongAttempt: previousWrongAttempt)
        if currentStroke == nil {
            currentStroke = StrokeChange(changes: [])
        }
        currentStroke?.changes.append(pixelChange)
    }

    private func undoLastStroke() {
        guard var currentDocument = document, let stroke = strokeHistory.popLast() else { return }

        var bitset = Bitset(data: currentDocument.correctPaintedBitset, bitCount: currentDocument.width * currentDocument.height)

        for change in stroke.changes.reversed() {
            if bitset.contains(change.pixelIndex) {
                bitset.set(change.pixelIndex, to: false)
                painting.completedPixelCount = max(0, painting.completedPixelCount - 1)
            }

            currentDocument.wrongAttempts.removeAll { $0.pixelIndex == change.pixelIndex }
            if let previousWrongAttempt = change.previousWrongAttempt {
                currentDocument.wrongAttempts.append(previousWrongAttempt)
            }
        }

        currentDocument.correctPaintedBitset = bitset.data
        painting.updatedAt = Date()
        painting.isCompleted = painting.completedPixelCount >= painting.totalPaintablePixelCount
        document = currentDocument
        persistDocument()
    }

    private func resetPainting() {
        guard var currentDocument = document else { return }

        currentDocument.correctPaintedBitset = Bitset(bitCount: currentDocument.width * currentDocument.height).data
        currentDocument.wrongAttempts.removeAll()
        painting.completedPixelCount = 0
        painting.isCompleted = false
        painting.updatedAt = Date()
        document = currentDocument
        strokeHistory.removeAll()
        persistDocument()
    }

    private func persistDocument() {
        guard let document, let store else { return }

        do {
            try store.savePaintingDocument(document, for: painting.id)
            try modelContext.save()
        } catch {
            errorMessage = "Your latest change could not be saved."
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

private struct StrokeChange {
    var changes: [PixelChange]
}

private struct PixelChange {
    var pixelIndex: Int
    var previousWrongAttempt: WrongAttempt?
}
