# Keyboard Tiling Shortcuts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Ctrl+Option+Arrow keyboard shortcuts for context-sensitive window tiling.

**Architecture:** A pure state machine (`KeyboardTileStateMachine`) maps `(currentTilePosition, arrowDirection) → newTilePosition`. A `KeyboardTileMonitor` listens for keyDown events via CGEventTap, detects the focused window's current tile position, runs the state machine, and applies the result via `WindowManager`. The `detectTilePosition` logic is extracted from `ZoomManager` into `WindowManager` so both features can share it.

**Tech Stack:** Swift 6, CGEventTap, AXUIElement, Swift Testing

---

### Task 1: Extract detectTilePosition into WindowManager

**Files:**
- Modify: `Sources/Swipey/WindowManager.swift:207-260`
- Modify: `Sources/Swipey/ZoomManager.swift:112-141`

**Step 1: Add detectTilePosition and framesMatch to WindowManager**

Add these methods at the end of `WindowManager.swift`, before the closing brace of the class, after the existing `setSize` method:

```swift
// MARK: - Tile position detection

/// Try to match the window's current frame to a known tile position.
/// Returns nil if the window doesn't match any tile position (untiled).
func detectTilePosition(of window: AXUIElement, on screen: NSScreen) -> TilePosition? {
    guard let cgPos = getPosition(of: window),
          let cgSize = getSize(of: window) else { return nil }

    guard let mainScreen = NSScreen.screens.first else { return nil }
    let nsOrigin = CGPoint(x: cgPos.x, y: mainScreen.frame.height - cgPos.y - cgSize.height)
    let windowFrame = CGRect(origin: nsOrigin, size: cgSize)

    let candidates: [TilePosition] = [
        .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .maximize,
    ]

    for position in candidates {
        let tileFrame = position.frame(for: screen)
        if framesMatch(windowFrame, tileFrame, tolerance: 10) {
            return position
        }
    }

    return nil
}

/// Check if window is in native fullscreen via AXFullScreen attribute.
func isFullscreen(_ window: AXUIElement) -> Bool {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
    return err == .success && (value as? Bool) == true
}

private func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
    return abs(a.origin.x - b.origin.x) <= tolerance
        && abs(a.origin.y - b.origin.y) <= tolerance
        && abs(a.width - b.width) <= tolerance
        && abs(a.height - b.height) <= tolerance
}
```

**Step 2: Update ZoomManager to use WindowManager's detectTilePosition**

In `ZoomManager.swift`, replace the private `detectTilePosition` and `framesMatch` methods (lines 112–141) with a delegation to `windowManager`:

```swift
private func detectTilePosition(of window: AXUIElement, on screen: NSScreen) -> TilePosition? {
    return windowManager.detectTilePosition(of: window, on: screen)
}
```

Delete the `framesMatch` method entirely from ZoomManager.

**Step 3: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds with no errors.

**Step 4: Run existing tests**

Run: `swift test 2>&1 | tail -10`
Expected: All existing tests pass (ZoomToggleStateMachine, ZoomFrameCalculator, GridSnapshot).

**Step 5: Commit**

```bash
git add Sources/Swipey/WindowManager.swift Sources/Swipey/ZoomManager.swift
git commit -m "refactor: extract detectTilePosition into WindowManager"
```

---

### Task 2: Create KeyboardTileStateMachine with tests

**Files:**
- Create: `Sources/Swipey/KeyboardTileStateMachine.swift`
- Create: `Tests/SwipeyTests/KeyboardTileStateMachineTests.swift`

**Step 1: Write the state machine**

Create `Sources/Swipey/KeyboardTileStateMachine.swift`:

```swift
/// Pure state machine: given a window's current tile position and an arrow direction,
/// returns the new tile position (or nil for no-op).
public enum KeyboardTileStateMachine: Sendable {

    public enum ArrowDirection: Sendable {
        case left, right, up, down
    }

    /// Returns the target tile position, or nil if no transition applies.
    public static func transition(from current: TilePosition?, direction: ArrowDirection) -> TilePosition? {
        switch (current, direction) {
        // From untiled (nil)
        case (nil, .left):  return .leftHalf
        case (nil, .right): return .rightHalf
        case (nil, .up):    return .maximize
        case (nil, .down):  return nil

        // From left half
        case (.leftHalf, .up):    return .topLeftQuarter
        case (.leftHalf, .down):  return .bottomLeftQuarter
        case (.leftHalf, .right): return .rightHalf
        case (.leftHalf, .left):  return nil

        // From right half
        case (.rightHalf, .up):    return .topRightQuarter
        case (.rightHalf, .down):  return .bottomRightQuarter
        case (.rightHalf, .left):  return .leftHalf
        case (.rightHalf, .right): return nil

        // From top half
        case (.topHalf, .left):  return .topLeftQuarter
        case (.topHalf, .right): return .topRightQuarter
        case (.topHalf, .up):    return .maximize
        case (.topHalf, .down):  return .bottomHalf

        // From bottom half
        case (.bottomHalf, .left):  return .bottomLeftQuarter
        case (.bottomHalf, .right): return .bottomRightQuarter
        case (.bottomHalf, .up):    return .topHalf
        case (.bottomHalf, .down):  return .restore

        // From maximize
        case (.maximize, .up):    return .fullscreen
        case (.maximize, .down):  return .restore
        case (.maximize, .left):  return .leftHalf
        case (.maximize, .right): return .rightHalf

        // From fullscreen — only down to restore
        case (.fullscreen, .down): return .restore
        case (.fullscreen, _):     return nil

        // From top-left quarter
        case (.topLeftQuarter, .right): return .topRightQuarter
        case (.topLeftQuarter, .down):  return .bottomLeftQuarter
        case (.topLeftQuarter, .left):  return .leftHalf
        case (.topLeftQuarter, .up):    return .topHalf

        // From top-right quarter
        case (.topRightQuarter, .left):  return .topLeftQuarter
        case (.topRightQuarter, .down):  return .bottomRightQuarter
        case (.topRightQuarter, .right): return .rightHalf
        case (.topRightQuarter, .up):    return .topHalf

        // From bottom-left quarter
        case (.bottomLeftQuarter, .right): return .bottomRightQuarter
        case (.bottomLeftQuarter, .up):    return .topLeftQuarter
        case (.bottomLeftQuarter, .left):  return .leftHalf
        case (.bottomLeftQuarter, .down):  return .bottomHalf

        // From bottom-right quarter
        case (.bottomRightQuarter, .left):  return .bottomLeftQuarter
        case (.bottomRightQuarter, .up):    return .topRightQuarter
        case (.bottomRightQuarter, .right): return .rightHalf
        case (.bottomRightQuarter, .down):  return .bottomHalf

        // restore is an action, not a state — treat as untiled
        case (.restore, _): return nil

        default: return nil
        }
    }
}
```

**Step 2: Write comprehensive tests**

Create `Tests/SwipeyTests/KeyboardTileStateMachineTests.swift`:

```swift
import Testing
@testable import SwipeyLib

@Suite("KeyboardTileStateMachine Tests")
struct KeyboardTileStateMachineTests {

    typealias SM = KeyboardTileStateMachine
    typealias Dir = SM.ArrowDirection

    // MARK: - From untiled

    @Test("Untiled: arrows tile to halves or maximize")
    func fromUntiled() {
        #expect(SM.transition(from: nil, direction: .left) == .leftHalf)
        #expect(SM.transition(from: nil, direction: .right) == .rightHalf)
        #expect(SM.transition(from: nil, direction: .up) == .maximize)
        #expect(SM.transition(from: nil, direction: .down) == nil)
    }

    // MARK: - From halves (subdivide to quarters)

    @Test("Left half: perpendicular arrows subdivide, right moves")
    func fromLeftHalf() {
        #expect(SM.transition(from: .leftHalf, direction: .up) == .topLeftQuarter)
        #expect(SM.transition(from: .leftHalf, direction: .down) == .bottomLeftQuarter)
        #expect(SM.transition(from: .leftHalf, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .leftHalf, direction: .left) == nil)
    }

    @Test("Right half: perpendicular arrows subdivide, left moves")
    func fromRightHalf() {
        #expect(SM.transition(from: .rightHalf, direction: .up) == .topRightQuarter)
        #expect(SM.transition(from: .rightHalf, direction: .down) == .bottomRightQuarter)
        #expect(SM.transition(from: .rightHalf, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .rightHalf, direction: .right) == nil)
    }

    @Test("Top half: perpendicular arrows subdivide, up maximizes")
    func fromTopHalf() {
        #expect(SM.transition(from: .topHalf, direction: .left) == .topLeftQuarter)
        #expect(SM.transition(from: .topHalf, direction: .right) == .topRightQuarter)
        #expect(SM.transition(from: .topHalf, direction: .up) == .maximize)
        #expect(SM.transition(from: .topHalf, direction: .down) == .bottomHalf)
    }

    @Test("Bottom half: perpendicular arrows subdivide, down restores")
    func fromBottomHalf() {
        #expect(SM.transition(from: .bottomHalf, direction: .left) == .bottomLeftQuarter)
        #expect(SM.transition(from: .bottomHalf, direction: .right) == .bottomRightQuarter)
        #expect(SM.transition(from: .bottomHalf, direction: .up) == .topHalf)
        #expect(SM.transition(from: .bottomHalf, direction: .down) == .restore)
    }

    // MARK: - From maximize

    @Test("Maximize: up goes fullscreen, down restores, sides go to halves")
    func fromMaximize() {
        #expect(SM.transition(from: .maximize, direction: .up) == .fullscreen)
        #expect(SM.transition(from: .maximize, direction: .down) == .restore)
        #expect(SM.transition(from: .maximize, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .maximize, direction: .right) == .rightHalf)
    }

    // MARK: - From fullscreen

    @Test("Fullscreen: only down restores, others are no-op")
    func fromFullscreen() {
        #expect(SM.transition(from: .fullscreen, direction: .down) == .restore)
        #expect(SM.transition(from: .fullscreen, direction: .up) == nil)
        #expect(SM.transition(from: .fullscreen, direction: .left) == nil)
        #expect(SM.transition(from: .fullscreen, direction: .right) == nil)
    }

    // MARK: - From quarters (slide + expand)

    @Test("Top-left quarter: slide right/down, expand left/up")
    func fromTopLeftQuarter() {
        #expect(SM.transition(from: .topLeftQuarter, direction: .right) == .topRightQuarter)
        #expect(SM.transition(from: .topLeftQuarter, direction: .down) == .bottomLeftQuarter)
        #expect(SM.transition(from: .topLeftQuarter, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .topLeftQuarter, direction: .up) == .topHalf)
    }

    @Test("Top-right quarter: slide left/down, expand right/up")
    func fromTopRightQuarter() {
        #expect(SM.transition(from: .topRightQuarter, direction: .left) == .topLeftQuarter)
        #expect(SM.transition(from: .topRightQuarter, direction: .down) == .bottomRightQuarter)
        #expect(SM.transition(from: .topRightQuarter, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .topRightQuarter, direction: .up) == .topHalf)
    }

    @Test("Bottom-left quarter: slide right/up, expand left/down")
    func fromBottomLeftQuarter() {
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .right) == .bottomRightQuarter)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .up) == .topLeftQuarter)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .down) == .bottomHalf)
    }

    @Test("Bottom-right quarter: slide left/up, expand right/down")
    func fromBottomRightQuarter() {
        #expect(SM.transition(from: .bottomRightQuarter, direction: .left) == .bottomLeftQuarter)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .up) == .topRightQuarter)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .down) == .bottomHalf)
    }

    // MARK: - Multi-step sequences

    @Test("Untiled → left half → top-left quarter (two-step quarter tiling)")
    func twoStepQuarterTile() {
        let step1 = SM.transition(from: nil, direction: .left)
        #expect(step1 == .leftHalf)
        let step2 = SM.transition(from: step1, direction: .up)
        #expect(step2 == .topLeftQuarter)
    }

    @Test("Untiled → maximize → fullscreen (two-step fullscreen)")
    func twoStepFullscreen() {
        let step1 = SM.transition(from: nil, direction: .up)
        #expect(step1 == .maximize)
        let step2 = SM.transition(from: step1, direction: .up)
        #expect(step2 == .fullscreen)
    }

    @Test("Navigate all four quarters clockwise from top-left")
    func quarterNavigation() {
        var pos: TilePosition? = .topLeftQuarter
        pos = SM.transition(from: pos, direction: .right)
        #expect(pos == .topRightQuarter)
        pos = SM.transition(from: pos, direction: .down)
        #expect(pos == .bottomRightQuarter)
        pos = SM.transition(from: pos, direction: .left)
        #expect(pos == .bottomLeftQuarter)
        pos = SM.transition(from: pos, direction: .up)
        #expect(pos == .topLeftQuarter)
    }
}
```

**Step 3: Run tests to verify they compile and pass**

Run: `swift test --filter KeyboardTileStateMachine 2>&1 | tail -10`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add Sources/Swipey/KeyboardTileStateMachine.swift Tests/SwipeyTests/KeyboardTileStateMachineTests.swift
git commit -m "feat: add KeyboardTileStateMachine with full test coverage"
```

---

### Task 3: Create KeyboardTileMonitor

**Files:**
- Create: `Sources/Swipey/KeyboardTileMonitor.swift`

**Step 1: Write the monitor**

Create `Sources/Swipey/KeyboardTileMonitor.swift`:

```swift
import CoreGraphics
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "keyboard-tile")

/// Arrow key keycodes
private let kLeftArrow: Int64 = 0x7B
private let kRightArrow: Int64 = 0x7C
private let kDownArrow: Int64 = 0x7D
private let kUpArrow: Int64 = 0x7E

/// Required modifier flags: Ctrl + Option, without Cmd or Shift
private let kRequiredFlags: CGEventFlags = [.maskControl, .maskAlternate]
private let kExcludedFlags: CGEventFlags = [.maskCommand, .maskShift]

final class KeyboardTileMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let windowManager: WindowManager

    /// Called after a window is tiled via keyboard shortcut.
    var onWindowTiled: ((AXUIElement) -> Void)?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardTileMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create keyboard tile event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("[Swipey] Keyboard tile monitor started")
    }

    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // Check modifiers: require Ctrl+Option, reject if Cmd or Shift also held
        let flags = event.flags
        guard flags.contains(kRequiredFlags),
              flags.isDisjoint(with: kExcludedFlags) else {
            return Unmanaged.passUnretained(event)
        }

        // Map keycode to arrow direction
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let direction: KeyboardTileStateMachine.ArrowDirection
        switch keycode {
        case kLeftArrow:  direction = .left
        case kRightArrow: direction = .right
        case kDownArrow:  direction = .down
        case kUpArrow:    direction = .up
        default:
            return Unmanaged.passUnretained(event)
        }

        // Get the focused window
        guard let window = focusedWindow() else {
            return Unmanaged.passUnretained(event)
        }

        // Detect current tile position
        let currentPosition: TilePosition?
        if windowManager.isFullscreen(window) {
            currentPosition = .fullscreen
        } else if let screen = windowManager.screen(for: window) {
            currentPosition = windowManager.detectTilePosition(of: window, on: screen)
        } else {
            currentPosition = nil
        }

        // Run state machine
        guard let targetPosition = KeyboardTileStateMachine.transition(
            from: currentPosition, direction: direction
        ) else {
            return Unmanaged.passUnretained(event)  // no-op, pass through
        }

        // Determine the screen for tiling
        let screen = windowManager.screen(for: window) ?? NSScreen.main

        // Handle fullscreen exit specially
        if currentPosition == .fullscreen {
            windowManager.exitFullscreenAndTile(window: window, to: targetPosition, on: screen)
        } else {
            windowManager.tile(window: window, to: targetPosition, on: screen)
        }

        onWindowTiled?(window)

        logger.info("[Swipey] Keyboard tile: \(String(describing: currentPosition)) → \(String(describing: targetPosition))")

        return nil  // consume the event
    }

    private func focusedWindow() -> AXUIElement? {
        let pid: pid_t
        if NSRunningApplication.current.isActive {
            pid = ProcessInfo.processInfo.processIdentifier
        } else {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            pid = app.processIdentifier
        }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedValue
        )
        guard err == .success, let value = focusedValue else { return nil }
        return (value as! AXUIElement)
    }

    deinit {
        stop()
    }
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/Swipey/KeyboardTileMonitor.swift
git commit -m "feat: add KeyboardTileMonitor with Ctrl+Option+Arrow handling"
```

---

### Task 4: Wire KeyboardTileMonitor into AppDelegate

**Files:**
- Modify: `Sources/Swipey/AppDelegate.swift`

**Step 1: Add property and initialization**

In `AppDelegate.swift`, add a property after `gridResizeManager`:

```swift
private var keyboardTileMonitor: KeyboardTileMonitor!
```

In `applicationDidFinishLaunching`, after the `gridResizeManager.start()` line, add:

```swift
keyboardTileMonitor = KeyboardTileMonitor(windowManager: windowManager)
keyboardTileMonitor.onWindowTiled = { [weak self] window in
    self?.zoomManager.clearZoomState(for: window)
}
keyboardTileMonitor.start()
```

In the permission timer block, after the `gridResizeManager` re-check, add:

```swift
if self.accessibilityManager.isTrusted && !self.keyboardTileMonitor.isRunning {
    self.keyboardTileMonitor.start()
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Run all tests**

Run: `swift test 2>&1 | tail -15`
Expected: All tests pass, including the new KeyboardTileStateMachine tests.

**Step 4: Commit**

```bash
git add Sources/Swipey/AppDelegate.swift
git commit -m "feat: wire KeyboardTileMonitor into AppDelegate lifecycle"
```

---

### Task 5: Build and manual verification

**Step 1: Clean build**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds with no warnings.

**Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -15`
Expected: All tests pass.

**Step 3: Manual testing checklist (for the developer)**

Test with a real window (e.g., Terminal):
- [ ] Ctrl+Opt+Left → tiles to left half
- [ ] Ctrl+Opt+Up → subdivides to top-left quarter
- [ ] Ctrl+Opt+Right → slides to top-right quarter
- [ ] Ctrl+Opt+Down → slides to bottom-right quarter
- [ ] Ctrl+Opt+Right → expands to right half
- [ ] Ctrl+Opt+Up from untiled → maximize
- [ ] Ctrl+Opt+Up from maximize → fullscreen
- [ ] Ctrl+Opt+Down from fullscreen → restore
- [ ] Verify gesture tiling still works normally
- [ ] Verify zoom toggle still works normally
- [ ] Verify Ctrl+Opt+Arrow does NOT trigger when Cmd is also held
