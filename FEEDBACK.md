# Editor Feedback Plan

Temporary implementation plan for the current editor adjustments.

## 1. Full-Screen Editor Layout

Status: completed

Goal: Make the editor feel like a full-screen painting surface with only navigation and the color bar competing for space.

Current findings:

- `PaintingEditorScreen` currently has a custom `EditorToolbar` with title, progress, grid, numbers, undo, and reset controls.
- `PixelCanvasView` no longer has its own aspect-ratio modifier, but `PixelGeometry` still aspect-fits the image inside the available canvas, which is correct for preserving pixel proportions.
- The remaining problem is UI chrome, not the internal image aspect ratio: the editor surface should occupy all available space between navigation/back and palette.

Implementation steps:

1. Remove `EditorToolbar` usage from `PaintingEditorScreen`.
2. Remove editor-local controls for undo, grid toggle, numbers toggle, and reset.
3. Keep normal navigation back behavior only. Prefer the system navigation back button unless custom full-screen behavior requires a minimal leading back button.
4. Keep `PixelCanvasView` stretched to the full available editor area and let `PixelGeometry` continue fitting the painting inside that area.
5. Remove the completed banner from the editor if it reduces canvas space; completion should be shown by the completed artwork itself.
6. Move reset access to `HomeScreen` card context menu next to Delete.
7. Implement `HomeScreen.reset(_:)` by loading the painting document, clearing `correctPaintedBitset` and `wrongAttempts`, setting progress metadata to zero, updating `updatedAt`, saving the document, regenerating preview, and saving SwiftData.
8. Keep delete behavior unchanged.

Files likely touched:

- `CozyPixels/Screens/Editor/PaintingEditorScreen.swift`
- `CozyPixels/Screens/Editor/EditorToolbar.swift`
- `CozyPixels/Screens/Home/HomeScreen.swift`
- `CozyPixels/Services/PaintingStore.swift` if a small shared reset helper is preferable
- `CozyPixels/Services/PreviewRenderer.swift` only if preview reset needs an existing API adjustment

Acceptance criteria:

- Editor has no undo, grid, numbers, or reset controls.
- Editor canvas fills all space not used by navigation and palette.
- Home card long-press context menu includes Reset and Delete.
- Reset from Home clears progress, wrong attempts, completion state, and preview.

## 2. Reliable Zoom And Pan

Status: completed

Goal: Users can pinch to zoom and pan the zoomed canvas at any time, even when a color is selected.

Current findings:

- `canvasGesture` only pans when `selectedPaletteColorID == nil`.
- A color is selected by default in `loadDocument`, so panning is effectively unavailable during normal painting.
- `DragGesture(minimumDistance: 0)` is used for painting, which conflicts with drag-to-pan.

Implementation steps:

1. Separate painting taps from panning drags.
2. Use a tap or near-zero movement gesture to paint a single pixel.
3. Use drag movement beyond a small threshold for panning.
4. Decide whether drag-paint remains in MVP after this change. If drag-paint is retained, require a clear mode distinction, because one-finger drag cannot reliably mean both paint and pan at the same time.
5. Keep pinch zoom independent and simultaneous with panning.
6. Clamp scale to existing min/max values.
7. Update `gestureStartTransform` so pan gestures accumulate correctly after zoom and after previous pans.
8. Add or update pure logic tests if any gesture decision logic is extracted.

Recommended interaction model:

- Tap paints the selected pixel.
- One-finger drag pans the canvas.
- Pinch zooms the canvas.
- Drag-paint can be deferred unless a second explicit interaction is introduced later.

Files likely touched:

- `CozyPixels/Screens/Editor/PaintingEditorScreen.swift`
- `CozyPixels/Rendering/CanvasTransform.swift` if offset clamping or helpers are added

Acceptance criteria:

- With a color selected, one-finger drag pans instead of being interpreted only as painting.
- Pinch zoom still works.
- Tapping still paints the intended pixel after zooming and panning.
- Coordinate mapping remains correct at non-default scale and offset.

## 3. Completion Presentation

Status: completed

Goal: When a painting is completed, show the whole finished artwork clearly.

Implementation steps:

1. Detect the transition from incomplete to completed inside `paint(at:canvasSize:document:)`.
2. When completion first occurs, set `transform = CanvasTransform()` and `gestureStartTransform = transform`.
3. Set `showGrid = false` on completion.
4. Since grid and numbers controls are being removed, consider defaulting `showGrid` to `false` permanently or only enabling any internal grid while painting if still desired.
5. Persist the final document and preview as currently done at the end of the stroke.

Files likely touched:

- `CozyPixels/Screens/Editor/PaintingEditorScreen.swift`
- `CozyPixels/Rendering/PixelCanvasRenderer.swift` only if grid default behavior changes globally

Acceptance criteria:

- Completing the final paintable pixel resets zoom and pan to the default transform.
- Completed painting is fully visible.
- Grid is not shown after completion.
- Final preview is still regenerated.

## 4. Simplified Color Bar

Status: completed

Goal: The palette bar should show only useful remaining work per color.

Current findings:

- `PaletteBarView` currently shows a swatch, color ID, and completed/total subtitle.
- It receives completed and total counts, so remaining counts can be computed without model changes.

Implementation steps:

1. Change each palette item to a single swatch button with the remaining pixel count overlaid on it.
2. Remove color ID text and completed/total subtitle.
3. Hide completed colors from the bar, unless hiding the selected color creates awkward state transitions.
4. If the selected color becomes complete, automatically select the next color with remaining pixels.
5. If no colors remain, clear `selectedPaletteColorID`.
6. Keep accessibility labels descriptive, for example `Color 3, 12 pixels remaining`.
7. Preserve deterministic palette order for remaining colors.

Recommended behavior:

- Hide completed colors.
- Auto-advance selection to the next remaining color when the current one is completed.

Files likely touched:

- `CozyPixels/Screens/Editor/PaletteBarView.swift`
- `CozyPixels/Screens/Editor/PaintingEditorScreen.swift`

Acceptance criteria:

- Palette items have no text under them.
- Each visible color displays only a remaining count on the swatch.
- Completed colors disappear from the palette bar.
- Selection remains valid as colors are completed.

## Verification

Status: completed

Run after implementation:

1. `xcodebuild test -project CozyPixels.xcodeproj -scheme CozyPixels -destination 'id=<simulator-id>'`
2. Manual simulator check on iPad-sized destination:
   - Open an incomplete painting.
   - Tap to paint several pixels.
   - Pinch zoom in.
   - Pan while a color is selected.
   - Tap after panning and verify the intended pixel is painted.
   - Complete a painting and verify the editor zooms out and hides grid.
   - Long-press a Home card and reset it.
