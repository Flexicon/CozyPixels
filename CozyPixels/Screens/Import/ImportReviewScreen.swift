import SwiftUI

struct ImportReviewScreen: View {
    let result: ImageImportResult
    let onCreatePainting: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = "Imported Painting"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Painting") {
                    TextField("Title", text: $title)
                    LabeledContent("Size", value: "\(result.document.width) x \(result.document.height)")
                    LabeledContent("Colors", value: "\(result.document.palette.count)")
                    LabeledContent("Paintable Pixels", value: "\(result.paintablePixelCount)")
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
