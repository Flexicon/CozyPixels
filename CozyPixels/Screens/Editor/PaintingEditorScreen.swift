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
    @State private var completionCelebrationToken = 0
    @State private var showCompletionCelebration = false

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

                        if showCompletionCelebration {
                            CompletionCelebrationOverlay(token: completionCelebrationToken)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
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
        .statusBarHidden(true)
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
        .sensoryFeedback(.success, trigger: completionCelebrationToken)
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
            presentCompletionCelebration()
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
        guard let preferredColorID else {
            selectedPaletteColorID = remainingColorIDs.first
            return
        }
        selectedPaletteColorID = remainingColorIDs.min { lhs, rhs in
            let lhsDistance = abs(lhs - preferredColorID)
            let rhsDistance = abs(rhs - preferredColorID)
            if lhsDistance == rhsDistance {
                return lhs > rhs
            }
            return lhsDistance < rhsDistance
        }
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

    private func presentCompletionCelebration() {
        completionCelebrationToken += 1

        withAnimation(.easeOut(duration: 0.18)) {
            showCompletionCelebration = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeIn(duration: 0.35)) {
                showCompletionCelebration = false
            }
        }
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

private struct CompletionCelebrationOverlay: View {
    let token: Int

    @State private var artworkScale = 0.82
    @State private var badgeScale = 0.65
    @State private var badgeOpacity = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)

            ConfettiBurst(token: token)

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.bounce, value: token)

                VStack(spacing: 8) {
                    Text("Painting Complete!")
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    Text("100% colored in")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.32), lineWidth: 1)
                }
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
            }
            .scaleEffect(artworkScale)
        }
        .task(id: token) {
            artworkScale = 0.82
            badgeScale = 0.65
            badgeOpacity = 0

            withAnimation(.spring(response: 0.48, dampingFraction: 0.58)) {
                artworkScale = 1.06
                badgeScale = 1.08
                badgeOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(520))

            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                artworkScale = 1
                badgeScale = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Painting complete")
    }
}

private struct ConfettiBurst: View {
    let token: Int

    @State private var isBursting = false

    private let pieces: [ConfettiPiece] = (0..<42).map { ConfettiPiece(id: $0) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotationEffect(.degrees(isBursting ? piece.endRotation : piece.startRotation))
                        .position(
                            x: piece.startX * proxy.size.width,
                            y: isBursting ? proxy.size.height * piece.endY : -24
                        )
                        .opacity(isBursting ? 0 : 1)
                        .animation(
                            .easeOut(duration: piece.duration).delay(piece.delay),
                            value: isBursting
                        )
                }
            }
        }
        .task(id: token) {
            isBursting = false
            await Task.yield()
            isBursting = true
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let size: CGSize
    let cornerRadius: CGFloat
    let startX: CGFloat
    let endY: CGFloat
    let startRotation: Double
    let endRotation: Double
    let duration: Double
    let delay: Double

    init(id: Int) {
        self.id = id

        let colors: [Color] = [.pink, .orange, .yellow, .green, .cyan, .purple]
        color = colors[id % colors.count]
        size = CGSize(width: 6 + CGFloat((id * 3) % 7), height: 10 + CGFloat((id * 5) % 10))
        cornerRadius = id.isMultiple(of: 3) ? 4 : 1.5
        startX = CGFloat((id * 37) % 100) / 100
        endY = 0.28 + CGFloat((id * 19) % 82) / 100
        startRotation = Double((id * 29) % 180)
        endRotation = startRotation + Double(id.isMultiple(of: 2) ? 360 : -360) + Double((id * 17) % 180)
        duration = 1.05 + Double((id * 11) % 55) / 100
        delay = Double((id * 7) % 28) / 100
    }
}
