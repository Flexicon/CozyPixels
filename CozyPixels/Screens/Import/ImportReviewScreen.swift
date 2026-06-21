import SwiftUI

struct ImportReviewScreen: View {
    let result: ImageImportResult
    let onCreatePainting: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(result: ImageImportResult, initialTitle: String, onCreatePainting: @escaping (String) async throws -> Void) {
        self.result = result
        self.onCreatePainting = onCreatePainting
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Painting") {
                    TextField("Title", text: $title)
                    if result.wasResized {
                        LabeledContent("Original Size", value: "\(result.originalWidth) x \(result.originalHeight)")
                    }
                    LabeledContent("Final Size", value: "\(result.document.width) x \(result.document.height)")
                    LabeledContent("Colors", value: "\(result.document.palette.count)")
                    LabeledContent("Paintable Pixels", value: "\(result.paintablePixelCount)")
                }

                if result.wasResized || result.wasQuantized {
                    Section {
                        Label("This image was pixelated into a playable painting.", systemImage: "wand.and.sparkles")
                        if result.wasQuantized {
                            Text("Colors were simplified to fit the 32-color palette limit.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if result.exceedsRecommendedSize {
                    Section {
                        Label(
                            "Large drawings may be slower or harder to paint on smaller screens.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating..." : "Create") {
                        Task {
                            await createPainting()
                        }
                    }
                    .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createPainting() async {
        isCreating = true
        errorMessage = nil

        do {
            try await onCreatePainting(title.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = "Could not save this painting or its preview. Please try again."
            isCreating = false
        }
    }
}
