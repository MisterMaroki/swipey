# Zoom Toggle Feature Design

## Summary

A keyboard-triggered zoom toggle that temporarily expands a tiled window for quick viewing, then snaps it back to its tiled position. Activated by pressing left Cmd then right Cmd (or vice versa) in quick succession.

## Motivation

When working in 2x2 or 4x4 tile layouts, users sometimes need more space in one window briefly — to read a long line, check a detail, etc. Rather than re-tiling or resizing, they can "zoom" the focused window temporarily and toggle it back.

## Hotkey Detection

**Trigger:** Left Cmd + Right Cmd pressed sequentially (either order) within 400ms.

**Implementation:** New `ZoomToggleMonitor` class using a `CGEventTap` listening for `.flagsChanged` events. Detects left Cmd (keycode 0x37) vs right Cmd (keycode 0x36) via `event.getIntegerValueField(.keyboardEventKeycode)`.

**Sequence tracking:**
1. First Cmd key pressed (record which side + timestamp)
2. First Cmd key released
3. Second Cmd key pressed (opposite side) within 400ms → trigger zoom toggle
4. If any non-modifier key pressed between steps, reset sequence

**Hold vs Toggle:**
- On activation, record timestamp
- If second Cmd key released within 500ms of activation → "hold" mode: collapse on release
- If released after 500ms or re-triggered → "toggle" mode: stays expanded until next double-Cmd

## Zoom Behavior

**Expand:** Focused window grows ~50% in each dimension from its tiled anchor point, clamped to screen bounds.
- Quarter tile (25% screen) → ~56% screen
- Half tile (50% screen) → ~75% screen
- Maximized → no-op
- Non-tiled window → no-op

**Anchor:** Window stays anchored to the corner/edge of its tile position. A top-left quarter tile expands rightward and downward.

**Animation:** Same 200ms ease-out as existing tile animations.

**State:** Dictionary keyed by window CFHash stores `{ originalTileFrame, isZoomed }`. Cleared when window is re-tiled via gesture.

## Architecture

### New Files
- `ZoomToggleMonitor.swift` — CGEventTap for flagsChanged, detects double-Cmd sequence
- `ZoomManager.swift` — zoom state tracking, expand/collapse coordination

### Modified Files
- `AppDelegate.swift` — initialize ZoomToggleMonitor and ZoomManager
- `WindowManager.swift` — add zoomExpand/zoomCollapse methods, notify ZoomManager on re-tile

### Component Flow
```
ZoomToggleMonitor (detects double-Cmd)
    → ZoomManager.toggle()
        → WindowManager.zoomExpand(window, from: tileFrame, anchor: position)
        → WindowManager.zoomCollapse(window, to: tileFrame)
```

## Edge Cases
- Window not currently tiled: hotkey is a no-op
- Window re-tiled while zoomed: zoom state clears, window takes new tile position
- Multiple monitors: zoom expansion clamped to the screen the window is on
- Rapid double-Cmd during animation: queued or ignored until current animation completes
