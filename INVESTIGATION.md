# Apple Pencil Input Fidelity Investigation Plan

## Goal

Determine whether perceived Pencil jank comes from rendering cost or from low-frequency/lossy Pencil event handling.

Primary symptoms:

- Finger panning feels acceptable.
- Pencil panning feels janky.
- Fast drag-paint sometimes skips pixels that the Pencil visibly crossed.

## Current Hypothesis

The app currently handles Pencil/finger input through standard gesture recognizers:

- `UIPanGestureRecognizer`
- `UIPinchGestureRecognizer`
- `UILongPressGestureRecognizer`
- `UITapGestureRecognizer`

Gesture recognizers may not provide enough point samples for fast discrete pixel painting, especially if the Pencil moves quickly across small cells.

For drag-paint, using only the latest recognizer location can miss intermediate cells between event samples.

## Step 1: Add Input Instrumentation

Add temporary debug logging or signposts around `CanvasInputOverlay`.

Measure:

- Input source: finger vs Pencil.
- Gesture type: pan, pinch, long press paint.
- Event phase.
- Timestamp.
- Location.
- Translation delta.
- Pixel index mapped from location.
- Time since previous sample.
- Distance from previous sample in screen points.
- Distance from previous sample in pixel cells.

Expected output should answer:

- Are Pencil events arriving less often than finger events?
- Are Pencil events arriving in bursts?
- Are skipped painted pixels caused by large jumps between sampled points?
- Is panning jank correlated with sparse input samples or with canvas render time?

## Step 2: Separate Rendering From Input Timing

Add counters for:

- Number of pan input events per second.
- Number of paint input events per second.
- Number of canvas redraws per second.
- Average time between input events.
- Max time between input events.

Test scenarios:

1. Finger pan slowly.
2. Finger pan quickly.
3. Pencil pan slowly.
4. Pencil pan quickly.
5. Pencil drag-paint slowly.
6. Pencil drag-paint quickly across a diagonal line.
7. Pencil drag-paint quickly across a horizontal line.

If Pencil input frequency is low or uneven while finger is fine, focus on input handling.

If Pencil input frequency is high but redraws are slow, focus on rendering.

## Step 3: Inspect Current Gesture Routing

Specifically inspect:

- Whether `UILongPressGestureRecognizer` delays paint start.
- Whether `UIPanGestureRecognizer` conflicts with long press.
- Whether `pan.require(toFail: longPress)` delays pan recognition.
- Whether Pencil input is going through the same pan path as finger input.
- Whether Pencil movement is being interpreted as pan instead of paint in some cases.

Important current risk:

```swift
pan.require(toFail: longPress)
```

This can delay pan recognition because the pan recognizer waits to see if long press succeeds.

## Step 4: Patch Drag-Paint Pixel Gaps First

Even with perfect input frequency, fast movement can skip cells if we only paint the current sampled pixel.

Patch strategy:

- Track the last painted pixel coordinate.
- On each new drag sample, compute all grid cells crossed between the last coordinate and current coordinate.
- Paint every crossed cell.
- Use integer grid line interpolation, similar to Bresenham line traversal.

Example behavior:

```text
previous pixel: (2, 5)
current pixel:  (8, 5)

paint:
(2,5), (3,5), (4,5), (5,5), (6,5), (7,5), (8,5)
```

This directly addresses skipped pixels during fast drag-paint.

Files likely touched:

- `InteractivePixelCanvas.swift`
- Maybe add a pure helper in `PixelGeometry.swift` or a new small utility file.

Add unit tests for:

- Horizontal interpolation.
- Vertical interpolation.
- Diagonal interpolation.
- Same-pixel duplicate avoidance.
- Out-of-bounds safety.

## Step 5: Prefer Touch Handling For Pencil Paint

If instrumentation shows recognizer samples are too sparse, add a custom `UIView` touch handler for Pencil paint.

Instead of relying only on `UILongPressGestureRecognizer`, use:

```swift
touchesBegan(_:with:)
touchesMoved(_:with:)
touchesEnded(_:with:)
touchesCancelled(_:with:)
```

For Pencil touches:

- Start painting immediately on `touchesBegan`.
- Use `event.coalescedTouches(for:)` inside `touchesMoved`.
- Process every coalesced touch location.
- Interpolate between pixel coordinates to fill gaps.

This is likely the highest-value Pencil-specific fix.

Finger behavior can remain unchanged initially.

## Step 6: Add Coalesced Touch Support

For Pencil drag-paint, process:

```swift
event.coalescedTouches(for: touch)
```

Why:

- iOS may deliver multiple high-resolution Pencil samples bundled into one event.
- Gesture recognizers usually expose only the recognizer's current location.
- Coalesced touches give the intermediate samples needed for smoother, more complete strokes.

Patch behavior:

```text
touchesMoved
  -> get coalesced touches
  -> map each touch location to a pixel
  -> interpolate from previous pixel to current pixel
  -> send each crossed pixel to paint engine
```

## Step 7: Decide Pencil Tool Semantics

We should make an explicit product decision:

Option A:

- Finger pans/zooms.
- Pencil paints immediately.
- Pencil does not pan.

Option B:

- Finger and Pencil can both pan.
- Pencil paints only after long press or paint mode.

Option C:

- A toolbar mode controls whether Pencil pans or paints.

Recommended for this app:

- Finger: pan/zoom.
- Pencil: paint immediately.
- Tap with Pencil: fill one pixel.
- Drag with Pencil: paint crossed pixels.
- Finger tap can still fill if desired.
- Finger long-press drag can remain optional.

This matches user expectations for a coloring app and removes ambiguity.

## Step 8: Patch Pencil Tap Fill

If Pencil paint is implemented through touch handling:

- `touchesBegan` should paint the initial pixel immediately.
- That fixes Pencil single-tap fill without waiting for a tap recognizer or long press.

Need to avoid duplicate paint on `touchesEnded`.

## Step 9: Patch Pan Responsiveness Separately

If Pencil should still be allowed to pan, then:

- Do not route Pencil pan through long-press-gated recognizers.
- Avoid `pan.require(toFail: longPress)` for Pencil.
- Consider separate recognizers:
  - Finger pan recognizer.
  - Pencil paint touch handling.
  - No Pencil pan unless explicit navigation mode exists.

If Pencil pan remains a requirement, add a dedicated Pencil pan path and measure its event frequency separately.

## Step 10: Keep Rendering Changes Minimal During Input Investigation

Avoid mixing this work with the UIKit retained renderer rewrite.

For this investigation:

- Keep current SwiftUI `Canvas`.
- Keep numbers visible.
- Keep number threshold at `18`.
- Keep the Core Text line cache because it is low-risk.
- Focus only on input fidelity and skipped cells.

This avoids confusing rendering regressions with input fixes.

## Step 11: Verification Checklist

Manual verification:

- Finger pan still works.
- Finger pinch still works.
- Finger tap fill still works if currently supported.
- Pencil tap fills immediately.
- Pencil drag-paint does not skip cells on fast horizontal strokes.
- Pencil drag-paint does not skip cells on fast vertical strokes.
- Pencil drag-paint does not skip cells on fast diagonal strokes.
- Wrong attempts still persist.
- Correct-only stroke behavior still works.
- No duplicate wrong attempts are created.
- Panning does not wait for long press.

Automated tests:

- Add pure tests for pixel-line interpolation.
- Add tests that duplicate points do not duplicate emitted pixels.
- Add tests for clamped/out-of-bounds paths if the helper handles bounds.

## Proposed Patch Order

1. Add pure `pixelsCrossed(from:to:)` helper and tests.
2. Use that helper in existing drag-paint path.
3. Manually verify skipped drag-paint pixels are fixed.
4. Add instrumentation for input sample frequency.
5. Add Pencil-specific touch handling with coalesced touches.
6. Make Pencil tap fill immediate.
7. Remove or reduce recognizer conflicts only after measurement confirms the issue.
8. Re-test finger pan, pinch, tap, Pencil tap, and Pencil drag-paint.

## Success Criteria

- Fast Pencil drag-paint no longer leaves gaps along the path.
- Pencil tap fills immediately.
- Pencil movement feels no worse than finger movement for equivalent interactions.
- Instrumentation shows whether Pencil samples are sparse, coalesced, or render-bound.
- No broad renderer rewrite is introduced as part of this patch.
