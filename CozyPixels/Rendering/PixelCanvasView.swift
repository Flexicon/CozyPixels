import SwiftUI

struct PixelCanvasView: View {
    let state: PixelCanvasRenderState
    var transform: CanvasTransform = CanvasTransform()

    var body: some View {
        Canvas { context, size in
            PixelCanvasRenderer(state: state, transform: transform).render(context: context, size: size)
        }
        .accessibilityLabel("Pixel canvas")
    }
}
