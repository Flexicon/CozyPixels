# Panning Performance Research

## Context

The editor renders a `64x64` painting with `SwiftUI.Canvas` in `PixelCanvasView`, driven by `PaintingEditorScreen` state. Panning updates `transform.offset` on every `UIPanGestureRecognizer` change. That state change invalidates the SwiftUI view and causes the full `Canvas` draw closure to run again.

Commenting out `drawNumbers` not helping much is consistent with the current renderer: numbers are only one part of the per-frame work. The base pixel pass, grid pass, state allocation, and SwiftUI invalidation still happen every pan frame.

## Highest-Probability Causes

### 1. Full redraw on every pan tick

`PaintingEditorScreen.handlePan` mutates `@State transform.offset` for every `.changed` event. Because the transform is part of `PixelCanvasView`, every event re-enters SwiftUI diffing and re-executes the `Canvas` renderer.

At `64x64`, a full-screen fit can draw all 4096 cells every frame. At high zoom, the visible range is smaller, but the frame still pays SwiftUI invalidation and setup costs.

Why this matters:

- Apple drawing guidance says to draw minimally and avoid redrawing unchanged content.
- Panning does not change the painting content; it only changes where content appears.
- The current implementation recomputes and redraws content instead of moving already-rendered content.

Likely fix direction:

- Render static painting layers into cached `CGImage`s, then draw those images with nearest-neighbor scaling during pan.
- Treat panning/zooming as a transform/compositing operation where possible, not as a full cell-by-cell repaint.
- If staying with `Canvas`, cache expensive render inputs outside the draw closure.

### 2. Per-frame rebuilding of derived state

`PixelCanvasRenderer.render` rebuilds these every frame:

- `Bitset(data: document.correctPaintedBitset, bitCount: ...)`
- `Dictionary(uniqueKeysWithValues: document.palette.map { ... })`
- `Dictionary(uniqueKeysWithValues: document.wrongAttempts.map { ... })`
- `isDocumentCompleted(...)`, which scans all target pixels
- `visiblePixelRange(...)`

For 4096 pixels these are not huge individually, but doing them on every pan callback adds allocator pressure and CPU overhead. This also makes panning performance depend on document complexity even when no paint state changed.

Likely fix direction:

- Introduce a render cache/view model for derived values that only changes when `document` changes.
- Cache `paletteByID`, `wrongAttemptsByPixel`, `Bitset`, `isCompleted`, and potentially per-color/pixel metadata.
- Remove `state.scale`; it appears redundant because `transform.scale` is already passed and used by geometry.

### 3. Thousands of path/color operations per frame

`drawPixels` creates a `CGRect`, `Path(rect)`, and fill operation for each visible paintable pixel. A full 64x64 viewport means up to 4096 path creations and fills per frame, plus color bridging through `targetColor.swiftUIColor`.

This remains true after disabling numbers. The base cells are likely the dominant path if numbers are off.

Likely fix direction:

- Prefer image-based rendering for the base grid:
- Build a low-resolution `CGImage` where each logical painting pixel is one bitmap pixel.
- Draw that image scaled up with `interpolationQuality = .none`.
- Maintain separate images/layers for target colors, gray unpainted state, wrong attempts, highlights, and completed pixels as needed.
- Update only affected bitmap pixels after painting, not every pan frame.

### 4. Grid is drawn even when UI state says grid is hidden

`PixelCanvasRenderState` includes `showGrid`, but `render` currently draws the grid whenever `!isCompleted && geometry.cellSize >= 3`:

```swift
if !isCompleted, geometry.cellSize >= 3 {
    drawGrid(...)
}
```

This ignores `state.showGrid`. At common zoom levels the grid path is rebuilt and stroked during every pan even if the user has not enabled grid display.

This is probably not the whole problem, but it is a clear bug and unnecessary per-frame work.

Likely fix direction:

- Change the condition to include `state.showGrid`.

### 5. Canvas size may force large backing work

The `Canvas` is full-screen. On iPad, the backing render target can be several million physical pixels. Even if only 4096 logical cells are drawn, compositing a full-screen transparent/SwiftUI canvas can be expensive, especially while updating at gesture frequency.

Likely fix direction:

- Profile whether the app is CPU-bound in renderer code or GPU/compositing-bound.
- Mark custom UIKit views opaque if moving to `UIViewRepresentable` and the background is fully covered.
- Avoid transparent layers where possible.
- Consider a custom `UIView` or `CALayer` stack if SwiftUI `Canvas` continues to invalidate too broadly.

## Medium-Probability Causes

### 6. SwiftUI parent body recomputation during pan

Every `transform` update re-evaluates `PaintingEditorScreen.body`. That can recompute non-canvas views too. The palette bar receives count dictionaries from functions in body:

```swift
completedCountsByColorID(for: document)
totalCountsByColorID(for: document)
```

Those functions scan the document. During panning, the document has not changed, but these values may still be recomputed as the body updates.

Likely fix direction:

- Move derived palette counts into cached state updated only after painting/loading.
- Split the canvas into a child view whose state changes do not cause palette recomputation.
- Keep gesture transform state as local as possible to the rendering surface.

### 7. `Canvas` may not be the best fit for mutable pixel art

`Canvas` is convenient, but it still executes a drawing closure in response to SwiftUI invalidation. Pixel art panning is closer to moving/scaling a texture than redrawing vector content.

Likely fix direction:

- Test a `UIViewRepresentable` wrapping a custom `UIView` with cached `CGImage` layers.
- Use `draw(_:)` only when content changes or when a transform requires a redraw.
- For pan-only movement, consider layer transforms (`contentsGravity`, `contentsRect`, affine transforms) before redrawing.

### 8. Text was expensive, but disabling it only removed one layer

`drawNumbers` creates `CTLine`s per palette ID, then loops over visible cells and draws text. This is expensive at high zoom, but it is gated by `cellSize >= 18` and `showNumbers`.

If disabling it had little effect, likely bottlenecks are elsewhere:

- SwiftUI invalidation/body recomputation.
- Pixel rectangle drawing.
- Full-screen canvas compositing.
- Grid path drawing.
- Derived state allocations.

Still, number rendering should eventually be cached or tiled because it can become a bottleneck once the base renderer is faster.

## Lower-Probability Or Situational Causes

### 9. Persistence during drag-paint, not plain panning

Panning itself does not save. Long-press paint stroke changes call `persistDocument()` during each changed pixel, which writes JSON and saves SwiftData. That can cause jank during painting gestures, but should not affect pure panning unless gestures conflict or a paint stroke is active.

Likely fix direction:

- Batch document writes until stroke end.
- Keep in-memory document changes immediate, but persist at throttled intervals or on `.ended`.

### 10. Gesture recognizer interaction

The overlay uses UIKit recognizers, which is good. However, panning requires long press to fail because of:

```swift
pan.require(toFail: longPress)
```

This can affect responsiveness at gesture start, but it is unlikely to cause continuous poor panning once the pan is active.

Likely fix direction:

- Confirm in Instruments whether recognizer callbacks are delayed or whether frame time is spent in drawing.

### 11. Anti-aliasing and subpixel alignment

Cell rectangles can land on fractional coordinates during pan. That can cause antialiasing/blending on many rectangle edges. For crisp pixel art this is undesirable visually and may cost extra.

Likely fix direction:

- For image drawing, set interpolation quality to `.none`.
- For custom CGContext drawing, disable antialiasing for pixel cells and grid as appropriate.
- Align rendered image destinations to physical pixel boundaries where feasible.

## Recommended Measurement Plan

Use a real iPad/iPhone if possible. Simulator results can mislead for graphics performance.

1. Run Instruments with Time Profiler while panning a 64x64 painting.
2. Look for time in `PixelCanvasRenderer.render`, `drawPixels`, `drawGrid`, `drawNumbers`, SwiftUI layout/diffing, CoreGraphics, and allocation functions.
3. Run Allocations while panning and check whether dictionaries, paths, colors, attributed strings, or arrays are being allocated every frame.
4. Run Core Animation and enable visual diagnostics such as updated regions to confirm whether the whole canvas/screen is invalidating during pan.
5. Repeat with `showGrid = false` actually respected, numbers off, and a test build that draws a single cached `CGImage` instead of per-cell paths.

Useful comparisons:

- Current renderer, numbers on.
- Current renderer, numbers off.
- Current renderer, grid truly off.
- Cached image renderer, no grid/no numbers.
- Cached image renderer plus overlay highlights.

## Suggested Fix Order

### Step 1: Remove obvious unnecessary work

- Respect `state.showGrid` before drawing the grid.
- Remove `scale` from `PixelCanvasRenderState` if unused.
- Cache palette count dictionaries in the editor instead of recomputing them from body during pan.

Expected impact: small to medium, low risk.

### Step 2: Cache render-derived state

- Build a `PixelCanvasRenderCache` when the document changes.
- Store `paletteByID`, `wrongAttemptsByPixel`, `bitset`, `isCompleted`, and color lookup values.
- Avoid dictionary and bitset reconstruction inside the draw closure.

Expected impact: medium, low to moderate risk.

### Step 3: Replace per-cell base drawing with image drawing

- Generate a `CGImage` for current visual pixel state at document resolution.
- Draw it scaled to the destination rect with nearest-neighbor interpolation.
- Regenerate/update the image only when painting state, selection highlight, wrong attempts, or completion state changes.

Expected impact: high. This directly addresses the suspected large-canvas/cell-count issue.

Tradeoff: selected-color highlighting currently changes many cells when selection changes. That can be a separate highlight mask image or can be folded into a regenerated low-res image because 64x64 is small.

### Step 4: Consider a custom UIKit renderer

- Wrap a custom `UIView` in `UIViewRepresentable` if SwiftUI `Canvas` continues to redraw too broadly.
- Use cached `CGImage`s and draw in `draw(_:)`, or use `CALayer.contents` for the base bitmap and transform the layer during pan.
- Make the view opaque if possible.

Expected impact: high if SwiftUI invalidation/compositing is the main bottleneck.

Tradeoff: more code and lifecycle handling than `Canvas`.

## Candidate Architecture For Fast Pixel Art Rendering

Use layered bitmap rendering:

- Base layer: low-resolution `CGImage` representing gray unpainted cells and painted original colors.
- Wrong-attempt layer: low-resolution transparent `CGImage` with attempted colors and alpha.
- Selection highlight layer: low-resolution transparent or opaque mask for cells matching selected color.
- Grid layer: vector path or generated image, only when enabled and only above zoom threshold.
- Number layer: generated tile/text cache, only above readable zoom threshold.

During pan:

- Do not rebuild these layers.
- Only update transform/destination rect.
- Draw cached images with `interpolationQuality = .none`.

During paint:

- Update one pixel in the base image or regenerate the 64x64 bitmap.
- Update wrong-attempt layer only for the affected pixel.
- Persist document outside the frame-critical path.

## Immediate Code Smells Found

- `showGrid` is ignored by `PixelCanvasRenderer.render`.
- `scale` in `PixelCanvasRenderState` appears unused except as an Equatable-invalidating value.
- `isDocumentCompleted` scans all paintable pixels every render even though `Painting.isCompleted` exists and completion changes only after painting.
- `PaletteBarView` count inputs are recomputed from the document in `PaintingEditorScreen.body`, so panning may trigger count scans unrelated to canvas movement.
- `drawCompletedImage` creates a completed `CGImage` inside render; completed paintings should cache that image.
- `PaletteColor.swiftUIColor` creates SwiftUI colors during pixel rendering; a cached `CGColor`/raw byte path would avoid repeated bridging.

## Bottom Line

The likely bottleneck is not just numbers. The current design treats panning as a full SwiftUI state update plus a full redraw of vector-like cell content. For pixel art, the fastest path is to make the painting a cached bitmap/texture and pan/zoom that bitmap, updating pixels only when the document changes.

The first implementation pass should fix the low-risk grid/state-cache issues, but the meaningful performance win will probably come from image-based rendering or a custom UIKit/CALayer-backed canvas.
