# Edge Resize Divider Design

**Date:** 2026-02-20
**Status:** Approved

## Summary

Replace the Ctrl+drag grid resize feature with direct draggable dividers on shared edges between tiled windows. Users hover over the gap between tiled windows, see a highlight and resize cursor, then drag to resize both sides simultaneously.

## Architecture

Replace `GridResizeManager` with `EdgeResizeManager` + `EdgeHandlePanel`.

- `EdgeResizeManager` discovers tiled windows, detects shared edges (reuses `GridSnapshot`), and creates/destroys `EdgeHandlePanel` instances.
- Each `EdgeHandlePanel` is a thin transparent `NSPanel` positioned over a shared edge gap. It handles hover (cursor change + highlight) and drag (resize adjacent windows).

### Lifecycle

Edge handles are rebuilt after:
- Any tile action (gesture or keyboard)
- Screen configuration changes
- Debounced at 100ms to avoid rapid rebuilds

Handles are removed when fewer than 2 tiled windows remain.

## Edge Handle Panel

- `NSPanel`, borderless, non-activating, floating window level
- Size: 6pt wide/tall hit area centered on the 1pt gap
- Vertical edges: 6pt wide, spans full shared height
- Horizontal edges: 6pt tall, spans full shared width

### Hover

- `NSTrackingArea` with `.mouseEnteredAndExited` + `.activeAlways`
- Cursor: `resizeLeftRight` (vertical) or `resizeUpDown` (horizontal)
- Highlight: 2pt semi-transparent accent line, fades in 0.15s on hover, out on exit

### Drag

1. `mouseDown`: record initial mouse position and initial frames of adjacent windows
2. `mouseDragged`: compute delta, apply snap, resize both windows via AXUIElement
3. `mouseUp`: finalize positions, trigger handle rebuild

### Snapping

- Snap targets: 1/3, 1/2, 2/3 of screen visible frame
- Detent zone: 10pt
- Haptic feedback via `NSHapticFeedbackManager` on snap

### Constraints

- Minimum window dimension: 200pt
- Edge cannot exceed screen visible frame

### Multi-window Propagation

Reuses `GridSnapshot.computePropagation()` — dragging a vertical divider between 4 quarter-tiled windows resizes all windows on both sides.

## Files

### New
- `EdgeHandlePanel.swift` — NSPanel subclass with hover/drag
- `EdgeResizeManager.swift` — handle lifecycle, window discovery, snap logic

### Modified
- `AppDelegate.swift` — create EdgeResizeManager, wire tile action callback
- `GestureMonitor.swift` — call rebuildHandles() after tile actions

### Removed
- `GridResizeManager.swift` — replaced by EdgeResizeManager

### Kept
- `GridSnapshot.swift` — edge detection and propagation reused as-is
