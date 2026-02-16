# Keyboard Tiling Shortcuts Design

## Problem

Users without trackpads (mouse + keyboard) cannot tile windows. Adding Ctrl+Option+Arrow keyboard shortcuts provides parity with the trackpad gesture system.

## Modifier

**Ctrl+Option+Arrow keys.** Does not conflict with macOS defaults, gesture system, or the zoom toggle (double-Cmd).

## Mental Model

Arrows move the window in that direction. The result is context-sensitive based on the window's current tile position:

- **From untiled**: arrows tile to halves or maximize
- **From a half**: perpendicular arrows subdivide into quarters; opposite arrow moves to the other half
- **From a quarter**: arrows slide to adjacent quarters; pressing into the edge you're already at expands back to a half
- **From maximize**: Up escalates to fullscreen; Down restores; Left/Right go to halves

## State Transition Table

### From untiled / restored

| Arrow | Result        |
|-------|---------------|
| Left  | Left half     |
| Right | Right half    |
| Up    | Maximize      |
| Down  | No-op         |

### From halves

| Current    | Arrow | Result               |
|------------|-------|----------------------|
| Left half  | Up    | Top-left quarter     |
| Left half  | Down  | Bottom-left quarter  |
| Left half  | Right | Right half           |
| Left half  | Left  | No-op                |
| Right half | Up    | Top-right quarter    |
| Right half | Down  | Bottom-right quarter |
| Right half | Left  | Left half            |
| Right half | Right | No-op                |
| Top half   | Left  | Top-left quarter     |
| Top half   | Right | Top-right quarter    |
| Top half   | Up    | Maximize             |
| Top half   | Down  | Bottom half          |
| Bottom half| Left  | Bottom-left quarter  |
| Bottom half| Right | Bottom-right quarter |
| Bottom half| Up    | Top half             |
| Bottom half| Down  | Restore              |

### From maximize

| Arrow | Result     |
|-------|------------|
| Up    | Fullscreen |
| Down  | Restore    |
| Left  | Left half  |
| Right | Right half |

### From quarters

| Current         | Arrow | Result               |
|-----------------|-------|----------------------|
| Top-left        | Right | Top-right (slide)    |
| Top-left        | Down  | Bottom-left (slide)  |
| Top-left        | Left  | Left half (expand)   |
| Top-left        | Up    | Top half (expand)    |
| Top-right       | Left  | Top-left (slide)     |
| Top-right       | Down  | Bottom-right (slide) |
| Top-right       | Right | Right half (expand)  |
| Top-right       | Up    | Top half (expand)    |
| Bottom-left     | Right | Bottom-right (slide) |
| Bottom-left     | Up    | Top-left (slide)     |
| Bottom-left     | Left  | Left half (expand)   |
| Bottom-left     | Down  | Bottom half (expand) |
| Bottom-right    | Left  | Bottom-left (slide)  |
| Bottom-right    | Up    | Top-right (slide)    |
| Bottom-right    | Right | Right half (expand)  |
| Bottom-right    | Down  | Bottom half (expand) |

## Architecture

Follows the same patterns as ZoomToggleMonitor:

### KeyboardTileStateMachine

Pure function: `(currentTilePosition, arrowDirection) -> TilePosition?`. Encodes the full transition table. Fully testable with no side effects. Returns `nil` for no-op transitions.

### KeyboardTileMonitor

- CGEventTap on `.keyDown` events
- Checks for Ctrl+Option modifier flags (`[.maskControl, .maskAlternate]`)
- Extracts arrow keycode (left=0x7B, right=0x7C, down=0x7D, up=0x7E)
- Detects current tile position of focused window via WindowManager
- Applies transition via KeyboardTileStateMachine
- Tiles the window via WindowManager
- Does NOT consume events (passes through, same as ZoomToggleMonitor)

### Integration

- AppDelegate creates KeyboardTileMonitor alongside other monitors
- WindowManager.detectTilePosition() already exists (used by ZoomManager)
- WindowManager.tileWindow() already handles all TilePosition values
- GestureMonitor and ZoomManager are unaffected

## Non-Goals

- No event consumption (shortcuts pass through to the system)
- No new tile positions beyond what gestures already support
- No customizable modifier keys (Ctrl+Option is fixed)
