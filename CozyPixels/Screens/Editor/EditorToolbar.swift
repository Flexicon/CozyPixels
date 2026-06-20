import SwiftUI

struct EditorToolbar: View {
    let title: String
    let progressText: String
    @Binding var showGrid: Bool
    @Binding var showNumbers: Bool
    let canUndo: Bool
    let undoAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(progressText) complete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView(value: progressValue)
                    .frame(maxWidth: 160)
            }

            Spacer()

            Toggle("Grid", isOn: $showGrid)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Grid")

            Toggle("Numbers", isOn: $showNumbers)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Numbers")

            Button("Undo", systemImage: "arrow.uturn.backward", action: undoAction)
                .disabled(!canUndo)
                .labelStyle(.iconOnly)

            Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive, action: resetAction)
                .labelStyle(.iconOnly)
        }
    }

    private var progressValue: Double {
        let numberText = progressText.replacingOccurrences(of: "%", with: "")
        return (Double(numberText) ?? 0) / 100
    }
}
