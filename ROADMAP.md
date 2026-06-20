# ROADMAP.md

## Product Direction

CozyPixels is a native SwiftUI iPadOS/iOS paint-by-number pixel art app.

Users import raster pixel art or start from bundled gallery art. The app converts each image into a finite numbered palette grid, shows an unpainted grayscale canvas, and lets users repaint matching cells by selecting palette colors.

## Current MVP Status

Status: feature-complete, release-hardening pending

Implemented:

* Native SwiftUI app shell with Home and Gallery tabs.
* SwiftData `Painting` metadata model.
* File-backed painting documents under Application Support.
* JSON `PaintingDocument` blobs with palette, target grid, completed bitset, and wrong attempts.
* Photo import through PhotosUI.
* ImageIO/CoreGraphics decoding and RGBA8 normalization.
* Exact color palette extraction with deterministic sorting.
* Import validation for maximum dimensions and palette size.
* Cached progress previews generated from painting state, not original images.
* Home grid sorted by `updatedAt` with progress cards and delete support.
* Bundled gallery manifest and gallery search.
* Gallery lifecycle rule: no `Painting` is created until the first correct pixel.
* SwiftUI Canvas editor with pan, zoom, tap paint, drag paint, grid toggle, number toggle, undo, reset, selected-color highlighting, and persisted wrong attempts.
* Canvas performance pass with visible-cell culling for pixels, grid, numbers, and checkerboard cells.
* Preview generation moved off the main actor after editor strokes.
* Unit tests covering core non-UI logic.

Verified most recently with:

```sh
xcodebuild test -scheme CozyPixels -destination 'id=A7C0D548-D51F-4AB0-80BA-34E9650E3F28'
```

Result: passing.

## Release Hardening

Status: next

These are the next implementation steps before calling the MVP shippable.

### 1. Remove Template and Debug Scaffolding

Status: pending

Tasks:

* Remove or keep strictly debug-only sample painting insertion from Home.
* Replace template UI tests with meaningful smoke tests.
* Remove generated placeholder comments from UI test files.
* Confirm no placeholder copy or sample-only affordances appear in release builds.

Acceptance criteria:

* Release build has no `Add Samples` affordance.
* UI tests assert app launch, Home empty state, Gallery presence, and core navigation.

### 2. Manual Device QA

Status: pending

Tasks:

* Test import from Photos on a physical iPad.
* Test import from Photos on a physical iPhone if available.
* Test bundled gallery start flow.
* Test app relaunch after painting correct and wrong cells.
* Test delete behavior removes SwiftData metadata and files.
* Test large accepted images in the `129...256` range.
* Test rejection for images above `256x256`.
* Test rejection for images above `64` exact colors.

Acceptance criteria:

* Import, paint, persist, preview, relaunch, and delete work on device.
* No known crash in normal MVP flows.

### 3. Performance Validation

Status: pending

Tasks:

* Profile editor rendering at `128x128` and `256x256` in Instruments.
* Profile drag-paint responsiveness with numbers enabled and disabled.
* Profile preview generation after completed strokes.
* Check home grid scrolling with many paintings.
* Record rough JSON blob sizes for `128x128` and `256x256` documents.

Acceptance criteria:

* `128x128` drawings feel smooth on target iPad hardware.
* `256x256` drawings remain usable, even if less comfortable.
* No further renderer rewrite is needed for MVP.

### 4. Persistence and Recovery Polish

Status: pending

Tasks:

* Decide whether a missing/corrupt SwiftData container should show a recoverable error instead of `fatalError`.
* Ensure missing preview regeneration remains reliable after background preview saves.
* Confirm failed background preview saves do not leave stale UI state.
* Consider an explicit preview-regeneration path for all paintings if cached files are deleted.

Acceptance criteria:

* Storage failures are understandable to users where recovery is possible.
* Missing preview files never break Home rendering.

### 5. Release Metadata and Privacy

Status: pending

Tasks:

* Confirm deployment target and supported device families.
* Confirm Photos privacy usage description is present and user-friendly.
* Confirm app icon and launch appearance.
* Prepare basic App Store privacy answers.
* Confirm no third-party dependencies are included.

Acceptance criteria:

* App archive is ready for TestFlight submission.
* Privacy behavior matches App Store metadata.

## Post-MVP Backlog

Do not start these until release hardening is complete unless a specific item becomes necessary during QA.

### Import Improvements

* Optional quantization.
* User-selectable palette size: `8`, `16`, `24`, `32`, `48`, `64`.
* Resize/crop import review for oversized images.
* Better JPG cleanup.
* Transparent pixel options.

### Gallery Improvements

* More bundled gallery items.
* Difficulty filters.
* Categories or featured sections.
* Gallery item progress badges.
* Remote CMS or downloadable packs later, not MVP.

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
* Backup and restore.
* Compact binary document format.
* Versioned document migrations.

### Sharing

* Export completed PNG.
* Export progress PNG.
* Share sheet.
* Timelapse generation.

## Non-Goals For MVP

* Backend CMS.
* Accounts or auth.
* Cloud sync.
* Export or sharing.
* Social features.
* In-app purchases.
* Advanced quantization.
* Full photo-to-paint-by-number conversion.
* PencilKit freehand drawing.
* Third-party image decoding, persistence, gestures, grid rendering, or palette extraction.

## Engineering Rules

* Keep the app Apple-device-first: Swift, SwiftUI, SwiftData, ImageIO/CoreGraphics, PhotosUI.
* Do not render one SwiftUI view per pixel.
* Do not store one SwiftData row per pixel.
* Keep rendering separate from persistence.
* Keep coordinate mapping separate from views.
* Keep pure logic testable outside SwiftUI.
* Use deterministic file formats and explicit user-facing errors.
* Use simulator destination IDs for `xcodebuild`, not simulator names.
