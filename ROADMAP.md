# ROADMAP.md

## Goal

Build a native SwiftUI iPadOS/iOS paint-by-number pixel art app.

The app lets users import raster images or choose bundled gallery images. It converts each image into a numbered palette grid. Users repaint the image by selecting colors and filling matching numbered pixels.

## Architectural Decision

Use native SwiftUI.

Do not use React Native, Flutter, Unity, SpriteKit, or a web wrapper for MVP.

Rationale:

* Apple-device-only target.
* Best deployment path to physical iPads.
* Native photo import.
* Native persistence.
* Direct access to CoreGraphics/ImageIO.
* No cross-platform build overhead.

## MVP Scope

Included:

* Home grid of started paintings.
* Photo import.
* Exact palette extraction.
* Pixel grid parsing.
* Local bundled gallery.
* Gallery search.
* Canvas editor.
* Pinch zoom and pan.
* Tap/drag painting.
* Grid toggle.
* Number display at readable zoom.
* Bottom horizontal palette.
* Correct painting.
* Persisted wrong attempts.
* Cached progress thumbnails.
* SwiftData metadata.
* File-backed painting blobs.

Not included:

* Backend CMS.
* Accounts/auth.
* Cloud sync.
* Export/share.
* Social features.
* In-app purchases.
* Advanced quantization.
* Full photo-to-paint-by-number conversion.
* PencilKit freehand drawing.

## Phase 0 — Create Xcode Project

Status: completed

Create a fresh Xcode project:

```txt
App template: iOS App
Language: Swift
Interface: SwiftUI
Storage: SwiftData if available in template
Targets: iOS + iPadOS
Minimum OS: iOS/iPadOS 17 or newer
```

Project name can be changed later. Use a neutral working name such as:

```txt
PaintByNumbers
```

Initial checks:

* App builds.
* App runs on iPad simulator.
* App runs on physical iPad.
* SwiftData container initializes.
* Basic tab/navigation shell works.

Suggested top-level navigation:

```txt
Home
Gallery
```

## Phase 1 — Core Data Types

Status: completed

Create the basic model and support types.

Files:

```txt
Models/Painting.swift
Models/PaintingDocument.swift
Models/PaletteColor.swift
Models/GalleryItem.swift
Utilities/Bitset.swift
```

Implement:

* `Painting` SwiftData model.
* `PaintingDocument` Codable blob.
* `PaletteColor`.
* `WrongAttempt`.
* `GalleryItem`.
* `Bitset`.

Acceptance criteria:

* `Painting` can be inserted into SwiftData.
* `PaintingDocument` can encode/decode to JSON.
* Bitset can set/get pixel completion by index.
* Unit tests cover bitset and pixel indexing.

## Phase 2 — File Storage

Status: completed

Create:

```txt
Services/PaintingStore.swift
```

Responsibilities:

* Create per-painting directory.
* Save `painting.json`.
* Load `painting.json`.
* Save `preview.png`.
* Delete painting directory.
* Keep file names deterministic.

Suggested structure:

```txt
Application Support/
  Paintings/
    <painting-id>/
      painting.json
      preview.png
```

Acceptance criteria:

* A fake `PaintingDocument` can be saved and loaded.
* Missing file errors are explicit.
* Corrupt JSON errors are explicit.
* Deleting a painting removes its files.

## Phase 3 — Image Import and Parsing

Status: completed

Create:

```txt
Services/ImageImportService.swift
Services/PaletteExtractor.swift
```

Implement import from image data:

1. Decode with ImageIO/CoreGraphics.
2. Normalize pixel format to RGBA8.
3. Validate dimensions.
4. Extract exact colors.
5. Sort palette deterministically.
6. Convert pixels to palette color IDs.
7. Create `PaintingDocument`.

Rules:

```txt
recommendedMaxDimension = 128
hardMaxDimension = 256
maxPaletteColors = 64
```

Behavior:

* `<= 128x128`: accept.
* `129...256`: accept with warning metadata or review UI.
* `> 256`: reject.
* `palette > 64`: reject for MVP.

Acceptance criteria:

* Small PNG imports.
* JPG imports if system decoder supports it.
* Oversized image fails clearly.
* Too many colors fails clearly.
* Transparent pixels are handled deterministically.
* Unit tests cover palette extraction and sorting.

## Phase 4 — Home Screen

Status: completed

Create:

```txt
Screens/Home/HomeScreen.swift
Screens/Home/PaintingCardView.swift
```

Home card displays:

* preview image
* title
* last updated timestamp
* progress percentage

Behavior:

* Imported paintings appear immediately.
* Cards sort by `updatedAt` descending.
* Empty state tells user to import or open Gallery.

Acceptance criteria:

* Home grid renders sample paintings.
* Tapping card opens editor.
* Deleting a painting works if implemented.
* Home uses cached preview, not original image.

## Phase 5 — Photo Import UI

Status: completed

Create:

```txt
Screens/Import/ImportImageButton.swift
Screens/Import/ImportReviewScreen.swift
```

Flow:

1. User taps import.
2. `PhotosPicker` opens.
3. User selects raster.
4. App loads data.
5. App parses image.
6. App creates `Painting`.
7. App stores `PaintingDocument`.
8. App creates initial preview.
9. App navigates to editor or returns to home.

Acceptance criteria:

* Import from Photos works on simulator/device.
* Import failure shows actionable error.
* Imported image creates a `Painting` immediately.
* Initial preview is grayscale numbered/progress state, not original image.

## Phase 6 — Bundled Gallery

Status: completed

Create:

```txt
Services/GalleryStore.swift
Screens/Gallery/GalleryScreen.swift
Screens/Gallery/GalleryDetailScreen.swift
Resources/Gallery/gallery.json
Resources/Gallery/*.png
```

Gallery manifest:

```json
[
  {
    "id": "sample-001",
    "title": "Sample Cat",
    "tags": ["animal", "easy"],
    "assetName": "gallery_sample_cat",
    "difficulty": "easy"
  }
]
```

Behavior:

* Load manifest from bundle.
* Display gallery grid.
* Search by title and tags.
* Tapping item opens preview/editor-like detail.
* Do not create `Painting` until first correct paint.

Acceptance criteria:

* Gallery loads bundled examples.
* Search filters title/tags.
* Opening gallery item does not create home entry.
* First correct pixel creates `Painting`.
* Wrong attempts before first correct pixel should either be blocked or kept transient until a real `Painting` exists.

Recommended MVP simplification:

```txt
For gallery previews, require selecting the correct color and painting one correct pixel before creating a Painting.
Wrong attempts before creation are visual-only and not persisted.
```

After creation, wrong attempts persist normally.

## Phase 7 — Canvas Rendering

Status: completed

Create:

```txt
Rendering/PixelCanvasView.swift
Rendering/PixelCanvasRenderer.swift
Rendering/CanvasTransform.swift
Rendering/PixelGeometry.swift
```

Start with SwiftUI `Canvas`.

Renderer inputs:

```swift
struct PixelCanvasRenderState {
    var document: PaintingDocument
    var selectedPaletteColorID: Int?
    var showGrid: Bool
    var showNumbers: Bool
    var scale: CGFloat
}
```

Render layers:

1. Background.
2. Empty/transparent cells.
3. Unpainted gray cells.
4. Selected-color matching highlight.
5. Correct painted cells.
6. Wrong attempts.
7. Grid overlay.
8. Numbers when readable.

Acceptance criteria:

* 32x32 renders smoothly.
* 64x64 renders smoothly.
* 128x128 remains usable.
* 256x256 is allowed but may be less comfortable.
* Numbers hide at low zoom.
* Grid toggle works.
* Selected color highlights matching unpainted cells.

## Phase 8 — Editor Gestures and Painting

Status: completed

Create:

```txt
Screens/Editor/PaintingEditorScreen.swift
Screens/Editor/PaletteBarView.swift
Screens/Editor/EditorToolbar.swift
```

Implement:

* Pinch to zoom.
* Drag to pan.
* Tap to paint.
* Drag-paint.
* Palette selection.
* Grid toggle.
* Number toggle if implemented.
* Undo last stroke.
* Reset.

Painting behavior:

```txt
Correct selected color:
  mark pixel complete
  remove wrong attempt on that pixel
  increment progress if newly completed
  update preview after stroke
  persist document
  update Painting.updatedAt

Incorrect selected color:
  persist wrong attempt
  do not increment progress
  keep correct number visible
  update Painting.updatedAt
```

Undo behavior for MVP:

* Undo last stroke.
* A stroke may contain one or more pixel changes.
* Store stroke history in memory during the editor session.
* Persistence of undo history is not required for MVP.

Acceptance criteria:

* User can complete a simple drawing.
* Correct pixels persist.
* Wrong attempts persist.
* Reopening app restores state.
* Drag-paint does not repeatedly process the same pixel in one stroke.
* Painting already completed pixels does nothing.

## Phase 9 — Preview Renderer

Status: pending

Create:

```txt
Services/PreviewRenderer.swift
```

Generate cached preview PNG from current progress.

Preview rules:

* Unpainted cells are gray.
* Correct cells are colored.
* Wrong attempts may be shown lightly or omitted.
* Completed drawings show full color.
* Preview must not use original image.

Update preview:

* after import
* after completed stroke
* after reset
* after completion

Acceptance criteria:

* Home card preview updates after painting.
* Preview generation does not block the editor noticeably.
* Preview file is persisted.
* Missing preview can be regenerated from `painting.json`.

## Phase 10 — Polish and Error States

Status: pending

Add user-facing states:

* empty home
* empty gallery
* import too large
* too many colors
* corrupt painting file
* missing gallery asset
* failed preview generation
* failed persistence

Add small UX improvements:

* selected palette color is visually obvious
* palette number is readable
* progress indicator is visible
* completion state is satisfying but simple
* large drawing warning for `129...256`

Acceptance criteria:

* No silent failures.
* No crashes on bad imports.
* No unusable tiny number text at low zoom.
* Editor remains usable on iPad mini.

## Phase 11 — Tests

Status: pending

Add tests for non-UI logic.

Priority tests:

```txt
BitsetTests
PaletteExtractorTests
PaintingDocumentCodableTests
PaintingProgressTests
CanvasTransformTests
GalleryLifecycleTests
```

Specific cases:

* `pixelIndex = y * width + x`
* bitset set/get
* palette deterministic sorting
* exact color extraction
* too many colors rejection
* oversized image rejection
* correct paint increments progress once
* wrong paint persists attempt
* duplicate wrong attempt is ignored
* correct paint removes wrong attempt
* imported image creates Painting immediately
* gallery image creates Painting only after first correct paint

## Phase 12 — Performance Pass

Status: pending

Profile after the MVP works.

Check:

* render cost at 128x128
* render cost at 256x256
* drag-paint responsiveness
* preview generation time
* JSON blob size
* app launch with many paintings
* home grid scrolling

Potential optimizations:

* cache rendered static layers
* render numbers only for visible cells
* skip grid at low zoom
* use custom `UIView` drawing if SwiftUI `Canvas` is not enough
* move preview rendering off main actor
* binary encode painting documents instead of JSON later

Do not optimize before measuring.

## Backlog After MVP

### Import Improvements

* Optional quantization.
* User-selectable palette size.
* Resize/crop import review.
* Dithered import mode.
* Better JPG cleanup.
* Transparent pixel options.

### Gallery Improvements

* Remote CMS.
* Downloadable gallery packs.
* Difficulty filters.
* Categories.
* Featured/new sections.
* Gallery item progress badges.

### Editor Improvements

* Fill all visible matching cells gesture.
* Long-press inspect.
* Haptics.
* Better Apple Pencil hover behavior where available.
* Session stats.
* Mistake counter.
* Hint mode.

### Persistence Improvements

* iCloud sync.
* Backup/restore.
* Compact binary document format.
* Versioned migrations.

### Sharing

* Export completed PNG.
* Export progress PNG.
* Share sheet.
* Timelapse generation.

## Build Order Summary

Implement in this exact order:

```txt
1. SwiftData Painting model
2. PaintingDocument + Bitset
3. PaintingStore file persistence
4. Image parser with exact palette extraction
5. Home screen with fake/sample paintings
6. Photo import flow
7. Bundled gallery manifest
8. Canvas renderer
9. Editor gestures
10. Painting rules and persistence
11. Cached previews
12. Tests
13. Polish
```

Do not start backend/CMS/export/quantization work until the MVP loop is complete:

```txt
import/gallery -> parse -> open editor -> paint -> persist -> preview -> resume
```
