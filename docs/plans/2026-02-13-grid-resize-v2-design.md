# Grid Resize v2 — Hover Handle Design

**Goal:** When windows are tiled by Swipey, shared edges get a drag handle that appears on hover, allowing the user to resize both windows simultaneously — like native macOS tiling.

## Architecture

### Tile Registry

`TileRegistry` tracks which windows are currently tiled. It stores `(AXUIElement, TilePosition, screen)` entries keyed by window hash. Windows are registered on tile and removed on restore/close.

When entries change, it recomputes shared edges using `GridSnapshot` and notifies `EdgeHandleController` to update overlays.

### Edge Handle Controller

`EdgeHandleController` owns a set of `EdgeHandlePanel` instances — one per shared edge. When the tile registry updates, it creates/removes/repositions panels to match the current shared edges.

### Edge Handle Panel

Each `EdgeHandlePanel` is a thin `NSPanel` (6pt wide for vertical edges, 6pt tall for horizontal) placed over a shared edge in NS screen coordinates.

**Hover behavior:**
- `NSTrackingArea` with `.mouseEnteredAndExited` + `.activeAlways`
- On enter: show a 1pt highlight line (adaptive color) centered in the panel, set cursor to `resizeLeftRight` or `resizeUpDown`
- On exit: hide highlight, reset cursor

**Drag behavior:**
- `mouseDown` captures initial mouse position and both window frames
- `mouseDragged` computes delta from initial position, applies it to both windows via AXUIElement `setPosition`/`setSize`
- `mouseUp` ends the drag

The panel must NOT be `ignoresMouseEvents` (unlike PreviewOverlay). It uses `level = .floating` and `styleMask = [.borderless, .nonactivatingPanel]` so it doesn't steal focus.

### Coordinate Systems

- `TilePosition.frame(for:)` returns NS coordinates (bottom-left origin)
- AXUIElement get/setPosition uses CG coordinates (top-left origin)
- Shared edge detection (`GridSnapshot`) works in CG coordinates
- `EdgeHandlePanel` frame is in NS coordinates (it's an NSPanel)
- Conversions happen at the boundary: registry stores CG frames, controller converts to NS for panel placement

### Pruning

A 1-second timer checks if tiled windows have moved away from their registered positions (user manually moved them, app repositioned, window closed). If so, remove them from the registry and update handles.

## Data Flow

```
GestureMonitor.handleEnded()
  → WindowManager.tile(window, position, screen)
  → TileRegistry.register(window, position, screen)
    → GridSnapshot recomputes shared edges
    → EdgeHandleController.updateHandles(edges)
      → Create/remove/reposition EdgeHandlePanels
```

```
User hovers shared edge
  → EdgeHandlePanel.mouseEntered → show highlight + resize cursor
  → EdgeHandlePanel.mouseDown → capture initial state
  → EdgeHandlePanel.mouseDragged → resize both windows via AX
  → EdgeHandlePanel.mouseUp → end drag
```

## What Gets Deleted

- `GridResizeManager.swift` — the Ctrl key + polling approach is replaced entirely
- All Ctrl key references in AppDelegate

## What Gets Reused

- `GridSnapshot` — shared edge detection logic and propagation math
- `GridSnapshotTests` — all existing tests remain valid

## Components Summary

| Component | Type | Responsibility |
|-----------|------|---------------|
| `TileRegistry` | Class | Track tiled windows, recompute edges on change |
| `EdgeHandleController` | Class (@MainActor) | Own and manage EdgeHandlePanels |
| `EdgeHandlePanel` | NSPanel subclass (@MainActor) | Hover detection, drag handling, visual feedback |
