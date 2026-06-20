# AGENTS.md

## Project

Build a native iPadOS/iOS SwiftUI app for paint-by-number pixel art.

Users can import raster images, mostly pixel arnto a finite color palette and a pixel grid. The editor displays a grayscale numbered version of the image. Users select a color from a horizontal palette bar and paint the matching numbered cells back into the original image.

The app is Apple-device-first. Do not introduce cross-platform frameworks.

## Platform

* Use Swift.
* Use SwiftUI.
* Target iOS/iPadOS latest stable SDK.
* Minimum OS can be iOS/iPadOS 17 or newer.
* When running `xcodebuild`, use a simulator `id=...` destination from the available destinations list instead of simulator `name=...`; duplicate simulator names across OS versions make name-based destinations unreliable in this workspace.
* Optimize primarily for:

  * latest iPad Air
  * 2024 iPad mini
  * modern iPhones as secondary support

## Dependency Policy

MVP should use Apple frameworks only unless a dependency has a very strong justification.

Preferred Apple APIs:

* SwiftUI for app structure and screens.
* SwiftData for persistent metadata.
* FileManager for binary project blobs and cached thumbnails.
* PhotosUI / PhotosPicker for user image import.
* ImageIO / CoreGraphics for raster loading and decoding.
* SwiftUI Canvas or a custom drawing surface for the editor.
* No PencilKit for MVP. Apple Pencil input should work through normal touch handling.

Do not add third-party packages for:

* image decoding
* persistence
* gestures
* grid rendering
* color palette extraction

A third-party package is allowed only if it materially reduces implementation complexity and does not create deployment friction.

## Core Product Rules

### Imported Images

Imported images become started drawings immediately after successful parsing.

The parser should accept common raster formats supported by ImageIO, especially:

* PNG
* JPG/JPEG
* HEIC if available through the system decoder

For MVP, imported images should be treated as pixel-art-like assets.

### Gallery Images

Gallery images are bundled locally in the app.

A gallery image does not create a user drawing until the user paints at least one correct pixel.

Gallery search should support title and tags from a local manifest.

No backend or CMS for MVP.

### Drawing Size Limits

Hard cap: `256x256`.

Recommended default import cap: `128x128`.

Behavior:

* Images up to `128x128` should import directly.
* Images between `129x129` and `256x256` may import, but the UI should warn that large drawings may be slower or harder to paint.
* Images above `256x256` must be rejected or resized through an explicit import flow.
* Never create one SwiftUI view per pixel.

### Palette Extraction

MVP behavior:

* Extract exact colors from pixel art images.
* Preserve alpha handling deterministically.
* Fully transparent pixels should be treated as background/empty unless the implementation explicitly supports transparent paint cells.
* Sort palette colors deterministically.

Suggested palette sorting:

1. Transparent/background colors last or excluded.
2. Remaining colors grouped by hue.
3. Then saturation.
4. Then brightness.
5. Then RGB value as final tie-breaker.

Each palette color receives a stable number starting at `1`.

If exact color count is too high, block import with a clear message.

Default MVP threshold:

```txt
maxPaletteColors = 64
```

Optional later behavior:

* Add import-time quantization.
* Let user choose palette size: `8`, `16`, `24`, `32`, `48`, `64`.

Do not build quantization unless the core MVP is complete.

## Data Model

Name the main persisted model `Painting`.

Use SwiftData for metadata and lightweight state.

Do not store a database row per pixel.

Recommended SwiftData model shape:

```swift
@Model
final class Painting {
    var id: UUID
    var title: String
    var sourceTypeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var width: Int
    var height: Int
    var paletteColorCount: Int

    var projectBlobFilename: String
    var previewFilename: String?

    var completedPixelCount: Int
    var totalPaintablePixelCount: Int
    var isCompleted: Bool

    init(...)
}
```

Use value types for decoded runtime state:

```swift
struct PaintingDocument: Codable {
    var version: Int
    var width: Int
    var height: Int
    var palette: [PaletteColor]
    var targetColorIndexByPixel: [UInt16]
    var correctPaintedBitset: Data
    var wrongAttempts: [WrongAttempt]
}
```

```swift
struct PaletteColor: Codable, Hashable, Identifiable {
    var id: Int
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
}
```

```swift
struct WrongAttempt: Codable, Hashable {
    var pixelIndex: Int
    var attemptedPaletteColorID: Int
    var createdAt: Date
}
```

Use `UInt16` for target palette IDs so larger palettes remain safe.

Pixel index formula:

```swift
let pixelIndex = y * width + x
```

## Persistence Rules

Store SwiftData metadata separately from binary drawing data.

Suggested file layout inside the app sandbox:

```txt
Application Support/
  Paintings/
    <painting-id>/
      painting.json
      preview.png
Gallery/
  bundled assets inside app bundle
```

`painting.json` should contain:

* width
* height
* palette
* target color index grid
* correct painted bitset
* persisted wrong attempts

Update `updatedAt` whenever a user paints, resets, renames, or otherwise changes the drawing.

Wrong attempts should persist.

Correct pixels should persist as a bitset.

## Rendering Rules

The editor must be rendered through one drawing surface.

Acceptable approaches:

1. SwiftUI `Canvas`
2. `UIViewRepresentable` wrapping a custom `UIView` with `draw(_:)`

Start with SwiftUI `Canvas`. Move to custom `UIView` only if profiling shows SwiftUI Canvas is insufficient.

Do not create `Rectangle`, `Text`, or `Button` views per pixel.

Rendering states:

* Unpainted pixel:

  * gray cell
  * number visible when zoom level is high enough
* Unpainted pixel matching selected palette color:

  * slightly darker gray cell
  * number visible when zoom level is high enough
* Correctly painted pixel:

  * full original color
  * no number
* Wrong attempt:

  * translucent attempted color
  * correct number remains visible above or visibly through the wrong color
* Empty/transparent pixel:

  * checkerboard or app background
  * not paintable unless explicitly supported

Grid overlay:

* Toggleable.
* Visible only when useful.
* Should not dominate at low zoom.
* Use crisp lines aligned to pixel boundaries.

Number overlay:

* Toggleable if easy.
* Automatically hidden below readable zoom.
* Must not tank frame rate.

## Canvas Interaction

Required editor gestures:

* Pinch to zoom.
* Drag to pan.
* Tap pixel to paint.
* Drag-paint across pixels.
* Toggle grid.
* Toggle numbers if implemented.
* Undo last stroke.
* Reset drawing.

Coordinate mapping must be centralized.

Create a type similar to:

```swift
struct CanvasTransform {
    var scale: CGFloat
    var offset: CGSize

    func screenPointToPixel(
        _ point: CGPoint,
        canvasSize: CGSize,
        imageSize: PixelSize
    ) -> PixelCoordinate?
}
```

Painting rules:

* If selected palette color equals target pixel color:

  * mark pixel as correctly painted
  * remove any wrong attempt for that pixel
  * update progress
  * update `updatedAt`
* If selected palette color does not equal target pixel color:

  * persist a wrong attempt for that pixel
  * keep the correct number visible
  * do not increment progress

If the user paints a pixel already correctly painted, do nothing.

If the user paints the same wrong color on the same pixel repeatedly, avoid duplicate wrong attempts.

## Apple Pencil

Apple Pencil should work through standard pointer/touch handling.

Do not add PencilKit for MVP.

The editor should support:

* finger tap
* finger drag
* Pencil tap
* Pencil drag

Avoid freehand drawing behavior. Input must resolve to discrete grid cells.

## UI Structure

### Home Screen

Displays started/imported paintings in a grid.

Each card shows:

* cached progress preview
* title
* last updated timestamp
* completion percentage

Preview should reflect current progress:

* unpainted pixels are gray
* correct pixels are colored
* wrong attempts may be shown if visually useful
* completed paintings show all colored pixels

Do not use the original imported image for home previews.

### Import Flow

User can import from Photos.

Flow:

1. Pick image.
2. Decode raster.
3. Validate dimensions.
4. Validate palette count.
5. Create `Painting`.
6. Store parsed project blob.
7. Generate initial gray preview.
8. Navigate to editor or return to home.

### Gallery Screen

Displays bundled gallery items.

Features:

* grid/list of available pixel art
* search by title and tags
* tap to preview/play
* no `Painting` created until first correct paint

Gallery manifest example:

```json
[
  {
    "id": "cat-001",
    "title": "Cat",
    "tags": ["animal", "easy"],
    "assetName": "gallery_cat_001",
    "difficulty": "easy"
  }
]
```

### Editor Screen

Required layout:

```txt
Top bar:
  back
  title
  progress
  grid toggle
  numbers toggle if implemented
  undo

Center:
  zoomable/pannable pixel canvas

Bottom:
  horizontally scrollable palette
```

Palette item:

* color swatch
* number
* completed count / total count if easy
* selected state

## Preview Generation

Use cached previews for the home grid.

Generate previews:

* after import
* after meaningful paint progress
* after reset
* when painting completes

Do not regenerate thumbnails on every home render.

A simple MVP strategy is to update the preview after each completed stroke, not every individual pixel during drag.

## Testing Requirements

Add tests for pure logic.

Prioritize:

* pixel index mapping
* palette extraction
* palette sorting
* bitset set/get behavior
* painting correct pixel
* painting wrong pixel
* preventing duplicate wrong attempts
* progress calculation
* gallery item does not create `Painting` until first correct paint
* imported image creates `Painting` immediately

UI tests are optional for MVP.

## Suggested Project Structure

```txt
CozyPixels/
  App/
    CozyPixelsApp.swift

  Models/
    Painting.swift
    PaintingDocument.swift
    PaletteColor.swift
    GalleryItem.swift

  Services/
    ImageImportService.swift
    PaletteExtractor.swift
    PaintingStore.swift
    GalleryStore.swift
    PreviewRenderer.swift

  Rendering/
    PixelCanvasView.swift
    PixelCanvasRenderer.swift
    CanvasTransform.swift
    PixelGeometry.swift

  Screens/
    Home/
      HomeScreen.swift
      PaintingCardView.swift

    Gallery/
      GalleryScreen.swift
      GalleryDetailScreen.swift

    Import/
      ImportImageButton.swift
      ImportReviewScreen.swift

    Editor/
      PaintingEditorScreen.swift
      PaletteBarView.swift
      EditorToolbar.swift

  Utilities/
    Bitset.swift
    DateFormatting.swift
    Color+Palette.swift

  Resources/
    Gallery/
      gallery.json
      gallery_cat_001.png
```

## Implementation Rules for AI Agents

* Keep implementation incremental.
* Prefer small, compile-safe commits.
* Keep `ROADMAP.md` phase `Status:` lines current. Initialize new phases as `Status: pending`, mark the active phase `Status: in progress`, and mark a phase `Status: completed` only after its acceptance criteria are implemented and verified.
* Do not rewrite large parts of the app without a reason.
* Do not introduce third-party dependencies without updating this file.
* Do not store per-pixel state in SwiftData rows.
* Do not render per-pixel SwiftUI views.
* Do not build a backend.
* Do not build export/share for MVP.
* Do not build quantization before the exact-color MVP works.
* Keep pure logic testable outside SwiftUI.
* Keep rendering separate from persistence.
* Keep coordinate mapping separate from views.
* Use deterministic data formats.
* Use explicit errors for import failures.

## MVP Definition of Done

MVP is complete when:

* User can import a pixel-art PNG/JPG.
* App parses dimensions and palette.
* App rejects images larger than `256x256`.
* App rejects images with too many exact colors.
* Imported image appears on the home screen immediately.
* Home screen shows a progress preview, not the original image.
* User can open the editor.
* User can zoom and pan.
* User can toggle grid.
* User can select a color from the bottom palette.
* User can paint correct cells.
* User can make persisted wrong attempts.
* Matching cells for the selected color are highlighted.
* Numbers appear only when readable.
* Progress persists after closing and reopening the app.
* Bundled gallery exists.
* Gallery image only becomes a `Painting` after the first correct pixel.
* Completed image displays as fully colored.
