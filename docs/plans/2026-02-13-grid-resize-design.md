# Grid Resize Design

Linked resizing of tiled windows so that dragging one window's edge resizes adjacent tiled windows along shared edges, maintaining the grid layout.

## Activation

User holds **Ctrl** while dragging a window edge. Without Ctrl, resize behaves normally.

## Detection Method

**Polling at 60Hz** while Ctrl is held. On Ctrl press, snapshot the grid; on Ctrl release, discard it.

## New Components

### GridResizeManager

Main coordinator. Responsibilities:
- CGEventTap for `.flagsChanged` events — observes Ctrl press/release (does not consume events)
- On Ctrl press: builds `GridSnapshot` for the screen under the cursor, starts 60Hz `DispatchSourceTimer`
- Each poll: queries window frames, detects edge changes, propagates to adjacent windows
- On Ctrl release: stops timer, discards snapshot
- Created by `AppDelegate`, independent of gesture system

### GridSnapshot

Value type capturing grid state at a moment in time:
- Queries all windows on the active screen
- Filters to windows whose frames look tiled (edges align to screen edges or other windows within 6pt tolerance)
- Builds shared edge list

## Shared Edge Detection

On Ctrl press:
1. Get screen under mouse cursor
2. Get all on-screen windows via `CGWindowListCopyWindowInfo`, resolve to AXUIElements
3. Get each window's frame
4. For each window pair, check for shared edges:
   - **Vertical**: Window A's right edge ~ Window B's left edge, with vertical overlap
   - **Horizontal**: Window A's bottom edge ~ Window B's top edge, with horizontal overlap
5. Only edges shared between two tiled windows are linked. Outer edges (screen boundary) are not.

### SharedEdge Structure

```
SharedEdge {
    windowA: AXUIElement
    windowB: AXUIElement
    axis: .vertical | .horizontal
    coordinate: CGFloat          // x (vertical) or y (horizontal) of the shared edge
    span: (start, end)           // overlapping range on the perpendicular axis
}
```

Tolerance: 6pt for edge matching (accounts for 4pt gap + rounding).

## Polling & Resize Propagation

60Hz loop while Ctrl held:

1. Query current frame of each snapshotted window
2. Compare to stored frame — identify which edges moved
3. For each moved edge that is part of a `SharedEdge`:
   - Compute delta
   - Find all windows sharing that edge coordinate
   - Resize adjacent windows by adjusting their corresponding edge
4. Update snapshot frames to current values

### Example: Two Halves

- Left-half right edge moves +50pt (OS did this via user drag)
- Right-half left edge moves +50pt, width shrinks by 50pt (GridResizeManager does this)

### Example: Four Quarters

- Dragging the center vertical edge propagates to all windows along that column
- Both top and bottom pairs adjust

## Feedback Loop Prevention

When GridResizeManager resizes an adjacent window:
- Mark it as `isAdjusting` for one poll cycle
- Next poll: if that window's frame changed, it's our own adjustment — update snapshot, don't propagate
- Clear `isAdjusting` after processing

## Edge Cases

- **Window closed while Ctrl held**: AXUIElement query fails — remove window and its shared edges from snapshot
- **Window moved (not resized)**: Position-only change does not propagate
- **No tiled windows on screen**: Ctrl press does nothing, no timer started
- **Accessibility permissions lost**: AXUIElement calls fail gracefully

## Performance

- Timer only runs while Ctrl is held (seconds at a time)
- 2-4 AXUIElement frame queries at 60Hz is negligible
- No persistent background cost

## Integration

- `AppDelegate` creates `GridResizeManager` alongside other managers
- Keyboard tap uses same `@convention(c)` + `Unmanaged` pattern as `ZoomToggleMonitor`
- Uses AXUIElement directly for frame queries and setting position/size
- No interaction with `GestureMonitor` or `GestureStateMachine`
