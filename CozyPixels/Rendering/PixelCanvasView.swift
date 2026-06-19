import SwiftUI

struct PixelCanvasView: View {
    let state: PixelCanvasRenderState
    var transform: CanvasTransform = CanvasTransform()

    var body: some View {
        Canvas { context, size in
            PixelCanvasRenderer(state: state, transform: transform).render(context: context, size: size)
        }
        .aspectRatio(CGFloat(state.document.width) / CGFloat(max(state.document.height, 1)), contentMode: .fit)
        .accessibilityLabel("Pixel canvas")
    }
}
