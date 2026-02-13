# Zoom Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a keyboard-triggered zoom toggle that temporarily expands tiled windows using a left+right Cmd key sequence.

**Architecture:** A `ZoomToggleStateMachine` (pure logic) detects the double-Cmd sequence. `ZoomToggleMonitor` wraps it in a CGEventTap. `ZoomManager` tracks zoom state and coordinates with `WindowManager` for animated expand/collapse. Frame calculations use anchored growth (50% per dimension, clamped to screen).

**Tech Stack:** Swift 6.0, AppKit, CoreGraphics CGEventTap, ApplicationServices AXUIElement

---

### Task 1: Add Test Target to Package.swift

**Files:**
- Modify: `Package.swift`
- Create: `Tests/SwipeyTests/` (directory)

**Step 1: Update Package.swift to include test target**

In `Package.swift`, add a test target that depends on a new library target. Since the app is an executable, we need to extract testable code into a library target.

Replace the entire `targets` array in `Package.swift` with:

```swift
targets: [
    .target(
        name: "SwipeyLib",
        path: "Sources/Swipey",
        exclude: ["main.swift", "Info.plist"],
        swiftSettings: [
            .define("SWIPEY_LIB")
        ]
    ),
    .executableTarget(
        name: "Swipey",
        dependencies: ["SwipeyLib"],
        path: "Sources/SwipeyApp"
    ),
    .testTarget(
        name: "SwipeyTests",
        dependencies: ["SwipeyLib"],
        path: "Tests/SwipeyTests"
    )
]
```

**Step 2: Create the thin executable entry point**

Create directory `Sources/SwipeyApp/` and file `Sources/SwipeyApp/main.swift`:

```swift
import AppKit
import SwipeyLib

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Step 3: Make AppDelegate public**

In `Sources/Swipey/AppDelegate.swift`, change `final class AppDelegate` to `public final class AppDelegate` and add `public init() { super.init() }` and make `applicationDidFinishLaunching` and `applicationWillTerminate` public.

**Step 4: Create placeholder test file**

Create `Tests/SwipeyTests/ZoomToggleStateMachineTests.swift`:

```swift
import Testing
@testable import SwipeyLib

@Suite("ZoomToggleStateMachine Tests")
struct ZoomToggleStateMachineTests {
    @Test("Placeholder")
    func placeholder() {
        #expect(true)
    }
}
```

**Step 5: Verify it compiles**

Run: `cd /Users/omarmaroki/Projects/swipey && swift build 2>&1`
Expected: Build succeeds

**Step 6: Run tests**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test 2>&1`
Expected: 1 test passes

**Step 7: Commit**

```bash
git add Package.swift Sources/SwipeyApp/ Tests/SwipeyTests/
git commit -m "feat: add test target and SwipeyLib extraction for testability"
```

---

### Task 2: Create ZoomToggleStateMachine (Pure Logic, TDD)

**Files:**
- Create: `Sources/Swipey/ZoomToggleStateMachine.swift`
- Create: `Tests/SwipeyTests/ZoomToggleStateMachineTests.swift` (replace placeholder)

This is the pure state machine that detects the left-Cmd + right-Cmd sequence. No CGEventTap — just inputs and outputs, fully testable.

**Step 1: Write the failing tests**

Replace `Tests/SwipeyTests/ZoomToggleStateMachineTests.swift` with:

```swift
import Testing
@testable import SwipeyLib

@Suite("ZoomToggleStateMachine Tests")
struct ZoomToggleStateMachineTests {

    // MARK: - Basic trigger detection

    @Test("Left then right Cmd triggers expand")
    func leftThenRight() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.right), at: 0.1) == .activated)
    }

    @Test("Right then left Cmd triggers expand")
    func rightThenLeft() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.right), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.right), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.1) == .activated)
    }

    // MARK: - Rejection cases

    @Test("Same side twice does not trigger")
    func sameSideTwice() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.1) == nil)
    }

    @Test("Non-modifier key between resets sequence")
    func nonModifierResets() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.nonModifierKey, at: 0.08) == nil)
        #expect(sm.feed(.cmdDown(.right), at: 0.1) == nil)  // should NOT trigger
    }

    @Test("Timeout rejects second key")
    func timeoutRejects() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.right), at: 0.5) == nil)  // 500ms > 400ms timeout
    }

    // MARK: - Hold vs toggle detection

    @Test("Quick release after activation signals hold-release")
    func quickRelease() {
        var sm = ZoomToggleStateMachine()
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.right), at: 0.1)
        // Release second key within 500ms of activation
        #expect(sm.feed(.cmdUp(.right), at: 0.3) == .holdReleased)
    }

    @Test("Slow release after activation signals toggle (no action)")
    func slowRelease() {
        var sm = ZoomToggleStateMachine()
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.right), at: 0.1)
        // Release second key after 500ms of activation
        #expect(sm.feed(.cmdUp(.right), at: 0.7) == nil)  // toggle mode, no action on release
    }

    // MARK: - Sequence after activation

    @Test("New sequence works after activation completes")
    func sequenceAfterActivation() {
        var sm = ZoomToggleStateMachine()
        // First activation
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.right), at: 0.1)
        _ = sm.feed(.cmdUp(.right), at: 0.7)  // slow release, toggle mode

        // Second activation (should work)
        #expect(sm.feed(.cmdDown(.right), at: 1.0) == nil)
        #expect(sm.feed(.cmdUp(.right), at: 1.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 1.1) == .activated)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test 2>&1`
Expected: FAIL — `ZoomToggleStateMachine` does not exist

**Step 3: Implement ZoomToggleStateMachine**

Create `Sources/Swipey/ZoomToggleStateMachine.swift`:

```swift
/// Pure state machine that detects a left-Cmd → right-Cmd (or right → left)
/// sequence and distinguishes hold vs toggle behavior.
public struct ZoomToggleStateMachine: Sendable {

    public enum CmdSide: Sendable {
        case left, right

        var opposite: CmdSide {
            switch self {
            case .left: return .right
            case .right: return .left
            }
        }
    }

    public enum Input: Sendable {
        case cmdDown(CmdSide)
        case cmdUp(CmdSide)
        case nonModifierKey
    }

    public enum Output: Sendable {
        /// Double-Cmd detected — expand the window.
        case activated
        /// Second key released quickly — collapse (hold mode).
        case holdReleased
    }

    private enum State: Sendable {
        case idle
        case firstKeyDown(side: CmdSide)
        case waitingForSecond(firstSide: CmdSide, releaseTime: CFAbsoluteTime)
        case activated(secondSide: CmdSide, activationTime: CFAbsoluteTime)
    }

    private var state: State = .idle

    /// Maximum time between first key release and second key press.
    private let sequenceTimeout: CFAbsoluteTime = 0.4
    /// Maximum hold duration to count as a "hold" (vs toggle).
    private let holdThreshold: CFAbsoluteTime = 0.5

    public init() {}

    /// Feed a keyboard event and optional action to perform.
    @discardableResult
    public mutating func feed(_ input: Input, at timestamp: CFAbsoluteTime) -> Output? {
        switch state {
        case .idle:
            if case .cmdDown(let side) = input {
                state = .firstKeyDown(side: side)
            }
            return nil

        case .firstKeyDown(let side):
            switch input {
            case .cmdUp(let upSide) where upSide == side:
                state = .waitingForSecond(firstSide: side, releaseTime: timestamp)
            case .nonModifierKey:
                state = .idle
            default:
                state = .idle
            }
            return nil

        case .waitingForSecond(let firstSide, let releaseTime):
            switch input {
            case .cmdDown(let downSide) where downSide == firstSide.opposite:
                if timestamp - releaseTime <= sequenceTimeout {
                    state = .activated(secondSide: downSide, activationTime: timestamp)
                    return .activated
                } else {
                    // Timeout — treat as new first key
                    state = .firstKeyDown(side: downSide)
                    return nil
                }
            case .cmdDown(let downSide) where downSide == firstSide:
                // Same side again — restart as new first key
                state = .firstKeyDown(side: downSide)
                return nil
            case .nonModifierKey:
                state = .idle
                return nil
            default:
                return nil
            }

        case .activated(let secondSide, let activationTime):
            if case .cmdUp(let upSide) = input, upSide == secondSide {
                state = .idle
                if timestamp - activationTime <= holdThreshold {
                    return .holdReleased
                }
                return nil  // toggle mode — no action on release
            }
            // Any other event while activated: ignore
            return nil
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test 2>&1`
Expected: All 8 tests pass

**Step 5: Commit**

```bash
git add Sources/Swipey/ZoomToggleStateMachine.swift Tests/SwipeyTests/ZoomToggleStateMachineTests.swift
git commit -m "feat: add ZoomToggleStateMachine with full TDD test coverage"
```

---

### Task 3: Create Zoom Frame Calculation (TDD)

**Files:**
- Create: `Sources/Swipey/ZoomFrameCalculator.swift`
- Create: `Tests/SwipeyTests/ZoomFrameCalculatorTests.swift`

Pure function that computes the expanded frame given a tile position and screen.

**Step 1: Write the failing tests**

Create `Tests/SwipeyTests/ZoomFrameCalculatorTests.swift`:

```swift
import Testing
@testable import SwipeyLib
import AppKit

@Suite("ZoomFrameCalculator Tests")
struct ZoomFrameCalculatorTests {

    // Use a mock screen visible frame: 1440x900 starting at (0, 0)
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("Quarter tile expands 50% in each dimension, anchored to corner")
    func topLeftQuarterExpands() {
        let tileFrame = TilePosition.topLeftQuarter.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .topLeftQuarter,
            visibleFrame: visibleFrame
        )
        // Width and height should be 1.5x the tile size
        #expect(expanded.width > tileFrame.width)
        #expect(expanded.height > tileFrame.height)
        #expect(abs(expanded.width - tileFrame.width * 1.5) < 1)
        #expect(abs(expanded.height - tileFrame.height * 1.5) < 1)
        // Top-left anchor: minX should stay the same, maxY should stay the same (NS coords)
        #expect(abs(expanded.minX - tileFrame.minX) < 1)
        #expect(abs(expanded.maxY - tileFrame.maxY) < 1)
    }

    @Test("Bottom-right quarter anchors to bottom-right corner")
    func bottomRightQuarterExpands() {
        let tileFrame = TilePosition.bottomRightQuarter.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .bottomRightQuarter,
            visibleFrame: visibleFrame
        )
        #expect(abs(expanded.maxX - tileFrame.maxX) < 1)
        #expect(abs(expanded.minY - tileFrame.minY) < 1)
    }

    @Test("Left half expands rightward, keeps left edge")
    func leftHalfExpands() {
        let tileFrame = TilePosition.leftHalf.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .leftHalf,
            visibleFrame: visibleFrame
        )
        #expect(abs(expanded.minX - tileFrame.minX) < 1)
        #expect(expanded.width > tileFrame.width)
        // Height should stay the same (already full height)
        #expect(abs(expanded.height - tileFrame.height) < 1)
    }

    @Test("Maximize returns nil (no-op)")
    func maximizeIsNoOp() {
        let tileFrame = TilePosition.maximize.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .maximize,
            visibleFrame: visibleFrame
        )
        // Should return the same frame since it's already full
        #expect(abs(expanded.width - tileFrame.width) < 1)
        #expect(abs(expanded.height - tileFrame.height) < 1)
    }

    @Test("Expanded frame is clamped to screen bounds")
    func clampedToScreen() {
        let tileFrame = TilePosition.topRightQuarter.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .topRightQuarter,
            visibleFrame: visibleFrame
        )
        #expect(expanded.minX >= visibleFrame.minX)
        #expect(expanded.minY >= visibleFrame.minY)
        #expect(expanded.maxX <= visibleFrame.maxX)
        #expect(expanded.maxY <= visibleFrame.maxY)
    }
}
```

**Step 2: Add `frame(forVisibleFrame:)` to TilePosition**

To make frame calculations testable without needing an NSScreen instance, add a method to `TilePosition` that takes a `CGRect` instead of `NSScreen`. In `Sources/Swipey/TilePosition.swift`, add this method after the existing `frame(for:)`:

```swift
/// Calculate the tile frame for a given visible frame rectangle.
/// Used for testing and zoom calculations without needing an NSScreen.
public func frame(forVisibleFrame visible: CGRect) -> CGRect {
    let margin: CGFloat = 2
    let gap: CGFloat = 4

    switch self {
    case .maximize:
        return visible.insetBy(dx: margin, dy: margin)
    case .leftHalf:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                      width: halfWidth, height: visible.height - margin * 2)
    case .rightHalf:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin + halfWidth + gap, y: visible.minY + margin,
                      width: halfWidth, height: visible.height - margin * 2)
    case .topHalf:
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin, y: visible.minY + margin + halfHeight + gap,
                      width: visible.width - margin * 2, height: halfHeight)
    case .bottomHalf:
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                      width: visible.width - margin * 2, height: halfHeight)
    case .topLeftQuarter:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin, y: visible.minY + margin + halfHeight + gap,
                      width: halfWidth, height: halfHeight)
    case .topRightQuarter:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin + halfWidth + gap,
                      y: visible.minY + margin + halfHeight + gap,
                      width: halfWidth, height: halfHeight)
    case .bottomLeftQuarter:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                      width: halfWidth, height: halfHeight)
    case .bottomRightQuarter:
        let halfWidth = (visible.width - margin * 2 - gap) / 2
        let halfHeight = (visible.height - margin * 2 - gap) / 2
        return CGRect(x: visible.minX + margin + halfWidth + gap, y: visible.minY + margin,
                      width: halfWidth, height: halfHeight)
    case .fullscreen, .restore:
        return .zero
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test --filter ZoomFrameCalculator 2>&1`
Expected: FAIL — `ZoomFrameCalculator` does not exist

**Step 4: Implement ZoomFrameCalculator**

Create `Sources/Swipey/ZoomFrameCalculator.swift`:

```swift
import Foundation

/// Calculates the expanded frame for a zoomed window, anchoring to the
/// appropriate corner/edge based on tile position.
public enum ZoomFrameCalculator {

    /// Growth factor per dimension (1.5 = 50% larger).
    private static let growthFactor: CGFloat = 1.5

    /// Returns the expanded frame for a given tile position, clamped to screen bounds.
    public static func expandedFrame(
        tileFrame: CGRect,
        position: TilePosition,
        visibleFrame: CGRect
    ) -> CGRect {
        let newWidth = min(tileFrame.width * growthFactor, visibleFrame.width)
        let newHeight = min(tileFrame.height * growthFactor, visibleFrame.height)

        let origin: CGPoint = anchoredOrigin(
            tileFrame: tileFrame,
            newSize: CGSize(width: newWidth, height: newHeight),
            position: position,
            visibleFrame: visibleFrame
        )

        var frame = CGRect(origin: origin, size: CGSize(width: newWidth, height: newHeight))

        // Clamp to screen bounds
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }

        return frame
    }

    /// Determines the origin for the expanded frame based on which corner/edge
    /// the tile position anchors to. Uses NS coordinates (bottom-left origin).
    private static func anchoredOrigin(
        tileFrame: CGRect,
        newSize: CGSize,
        position: TilePosition,
        visibleFrame: CGRect
    ) -> CGPoint {
        let dw = newSize.width - tileFrame.width
        let dh = newSize.height - tileFrame.height

        switch position {
        // Corners: anchor to the corner
        case .topLeftQuarter:
            // Anchor top-left (NS: minX stays, maxY stays → origin.y decreases by dh)
            return CGPoint(x: tileFrame.minX, y: tileFrame.minY - dh)
        case .topRightQuarter:
            // Anchor top-right (NS: maxX stays → origin.x decreases by dw, maxY stays)
            return CGPoint(x: tileFrame.minX - dw, y: tileFrame.minY - dh)
        case .bottomLeftQuarter:
            // Anchor bottom-left (NS: minX stays, minY stays)
            return CGPoint(x: tileFrame.minX, y: tileFrame.minY)
        case .bottomRightQuarter:
            // Anchor bottom-right (NS: maxX stays, minY stays)
            return CGPoint(x: tileFrame.minX - dw, y: tileFrame.minY)

        // Halves: anchor to the edge
        case .leftHalf:
            // Anchor left edge, center vertically
            return CGPoint(x: tileFrame.minX, y: tileFrame.minY - dh / 2)
        case .rightHalf:
            // Anchor right edge, center vertically
            return CGPoint(x: tileFrame.minX - dw, y: tileFrame.minY - dh / 2)
        case .topHalf:
            // Anchor top edge, center horizontally
            return CGPoint(x: tileFrame.minX - dw / 2, y: tileFrame.minY - dh)
        case .bottomHalf:
            // Anchor bottom edge, center horizontally
            return CGPoint(x: tileFrame.minX - dw / 2, y: tileFrame.minY)

        case .maximize, .fullscreen, .restore:
            return tileFrame.origin
        }
    }
}
```

**Step 5: Run tests to verify they pass**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test --filter ZoomFrameCalculator 2>&1`
Expected: All 5 tests pass

**Step 6: Commit**

```bash
git add Sources/Swipey/ZoomFrameCalculator.swift Sources/Swipey/TilePosition.swift Tests/SwipeyTests/ZoomFrameCalculatorTests.swift
git commit -m "feat: add ZoomFrameCalculator with anchored expansion logic"
```

---

### Task 4: Create ZoomToggleMonitor (CGEventTap Wrapper)

**Files:**
- Create: `Sources/Swipey/ZoomToggleMonitor.swift`

This wraps the state machine in a CGEventTap that listens for `.flagsChanged` events. Follows the same pattern as `GestureMonitor.swift`.

**Step 1: Implement ZoomToggleMonitor**

Create `Sources/Swipey/ZoomToggleMonitor.swift`:

```swift
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "zoom-toggle")

/// Left Cmd keycode
private let kLeftCmdKeycode: Int64 = 0x37
/// Right Cmd keycode
private let kRightCmdKeycode: Int64 = 0x36

final class ZoomToggleMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = ZoomToggleStateMachine()

    /// Called when double-Cmd is detected (expand/toggle).
    var onActivated: (() -> Void)?
    /// Called when hold-release is detected (collapse).
    var onHoldReleased: (() -> Void)?

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        // Listen for flagsChanged (modifier keys) and keyDown (to detect non-modifier keys)
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ZoomToggleMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)  // always pass through — never consume keyboard events
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,  // tail append — observe only, don't block
            options: .listenOnly,         // listen only — we never consume keyboard events
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create zoom toggle event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.warning("[Swipey] Zoom toggle monitor started")
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

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let timestamp = CFAbsoluteTimeGetCurrent()

        // Non-modifier key pressed — reset sequence
        if type == .keyDown {
            _ = stateMachine.feed(.nonModifierKey, at: timestamp)
            return
        }

        guard type == .flagsChanged else { return }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let input: ZoomToggleStateMachine.Input
        switch keycode {
        case kLeftCmdKeycode:
            input = flags.contains(.maskCommand) ? .cmdDown(.left) : .cmdUp(.left)
        case kRightCmdKeycode:
            input = flags.contains(.maskCommand) ? .cmdDown(.right) : .cmdUp(.right)
        default:
            return  // not a Cmd key
        }

        if let output = stateMachine.feed(input, at: timestamp) {
            switch output {
            case .activated:
                logger.warning("[Swipey] Double-Cmd detected — toggling zoom")
                onActivated?()
            case .holdReleased:
                logger.warning("[Swipey] Hold released — collapsing zoom")
                onHoldReleased?()
            }
        }
    }

    deinit {
        stop()
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/omarmaroki/Projects/swipey && swift build 2>&1`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Swipey/ZoomToggleMonitor.swift
git commit -m "feat: add ZoomToggleMonitor with CGEventTap for flagsChanged"
```

---

### Task 5: Create ZoomManager (State Tracking & Coordination)

**Files:**
- Create: `Sources/Swipey/ZoomManager.swift`

Tracks which windows are zoomed, coordinates expand/collapse with WindowManager.

**Step 1: Implement ZoomManager**

Create `Sources/Swipey/ZoomManager.swift`:

```swift
@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "zoom")

final class ZoomManager: @unchecked Sendable {
    private let windowManager: WindowManager

    /// Tracks zoomed windows: windowKey → (originalTileFrame in NS coords, tilePosition)
    private var zoomedWindows: [Int: ZoomState] = [:]

    struct ZoomState {
        /// The original tile frame in NS coordinates (before zoom expansion).
        let tileFrame: CGRect
        /// The tile position for anchor calculation.
        let position: TilePosition
        /// The screen the window is on.
        let screen: NSScreen
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    /// Toggle zoom on the currently focused window.
    func toggleFocusedWindow() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard err == .success, let window = focusedValue else {
            logger.warning("[Swipey] No focused window found")
            return
        }

        let axWindow = window as! AXUIElement
        let key = Int(CFHash(axWindow))

        if let state = zoomedWindows[key] {
            // Already zoomed — collapse
            collapse(window: axWindow, to: state)
            zoomedWindows.removeValue(forKey: key)
        } else {
            // Not zoomed — try to expand
            expand(window: axWindow, key: key)
        }
    }

    /// Collapse the focused window (hold-release mode).
    func collapseFocusedWindow() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard err == .success, let window = focusedValue else { return }

        let axWindow = window as! AXUIElement
        let key = Int(CFHash(axWindow))

        if let state = zoomedWindows[key] {
            collapse(window: axWindow, to: state)
            zoomedWindows.removeValue(forKey: key)
        }
    }

    /// Call this when a window is re-tiled via gesture to clear its zoom state.
    func clearZoomState(for window: AXUIElement) {
        let key = Int(CFHash(window))
        zoomedWindows.removeValue(forKey: key)
    }

    /// Whether the given window is currently zoomed.
    func isZoomed(_ window: AXUIElement) -> Bool {
        let key = Int(CFHash(window))
        return zoomedWindows[key] != nil
    }

    // MARK: - Private

    private func expand(window: AXUIElement, key: Int) {
        guard let screen = windowManager.screen(for: window) else { return }

        // Determine current tile position by matching the window frame
        guard let position = detectTilePosition(of: window, on: screen) else {
            logger.warning("[Swipey] Window is not in a recognized tile position — zoom skipped")
            return
        }

        let tileFrame = position.frame(for: screen)
        let expandedFrame = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: position,
            visibleFrame: screen.visibleFrame
        )

        zoomedWindows[key] = ZoomState(tileFrame: tileFrame, position: position, screen: screen)

        // Convert from NS coordinates to CG coordinates for AX
        windowManager.animateToNSFrame(window: window, frame: expandedFrame)

        logger.warning("[Swipey] Expanded \(String(describing: position)) window")
    }

    private func collapse(window: AXUIElement, to state: ZoomState) {
        windowManager.animateToNSFrame(window: window, frame: state.tileFrame)
        logger.warning("[Swipey] Collapsed window back to \(String(describing: state.position))")
    }

    /// Try to match the window's current frame to a known tile position.
    private func detectTilePosition(of window: AXUIElement, on screen: NSScreen) -> TilePosition? {
        guard let cgPos = windowManager.getWindowPosition(window),
              let cgSize = windowManager.getWindowSize(window) else { return nil }

        // Convert CG position (top-left origin) to NS position (bottom-left origin)
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let nsOrigin = CGPoint(x: cgPos.x, y: mainScreen.frame.height - cgPos.y - cgSize.height)
        let windowFrame = CGRect(origin: nsOrigin, size: cgSize)

        let candidates: [TilePosition] = [
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize
        ]

        for position in candidates {
            let tileFrame = position.frame(for: screen)
            if framesMatch(windowFrame, tileFrame, tolerance: 10) {
                return position
            }
        }

        return nil
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
```

**Step 2: Add helper methods to WindowManager**

In `Sources/Swipey/WindowManager.swift`, we need to expose a few things:

After the `screen(at:)` method (around line 205), add:

```swift
// MARK: - Public AX helpers (for ZoomManager)

func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
    return getPosition(of: window)
}

func getWindowSize(_ window: AXUIElement) -> CGSize? {
    return getSize(of: window)
}

/// Animate window to a frame specified in NS coordinates (bottom-left origin).
func animateToNSFrame(window: AXUIElement, frame nsFrame: CGRect) {
    guard let mainScreen = NSScreen.screens.first else { return }
    let cgOrigin = CGPoint(
        x: nsFrame.origin.x,
        y: mainScreen.frame.height - nsFrame.origin.y - nsFrame.height
    )
    animateTile(window: window, to: cgOrigin, size: nsFrame.size)
}
```

Also change `animateTile` from `private` to `fileprivate` (or just keep it `private` and use the new `animateToNSFrame` wrapper — the wrapper is cleaner).

Wait — `animateTile` is `private`. The new `animateToNSFrame` method calls it from within the same file, so no access change needed.

**Step 3: Verify it compiles**

Run: `cd /Users/omarmaroki/Projects/swipey && swift build 2>&1`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/Swipey/ZoomManager.swift Sources/Swipey/WindowManager.swift
git commit -m "feat: add ZoomManager for zoom state tracking and coordination"
```

---

### Task 6: Wire Everything Up in AppDelegate

**Files:**
- Modify: `Sources/Swipey/AppDelegate.swift`
- Modify: `Sources/Swipey/GestureMonitor.swift` (notify ZoomManager on tile)

**Step 1: Update AppDelegate to initialize zoom components**

In `Sources/Swipey/AppDelegate.swift`:

Add new properties after line 14 (`private var onboardingController`):

```swift
private var zoomToggleMonitor: ZoomToggleMonitor!
private var zoomManager: ZoomManager!
```

In `applicationDidFinishLaunching`, after `gestureMonitor.start()` (line 27), add:

```swift
zoomManager = ZoomManager(windowManager: windowManager)
zoomToggleMonitor = ZoomToggleMonitor()
zoomToggleMonitor.onActivated = { [weak self] in
    self?.zoomManager.toggleFocusedWindow()
}
zoomToggleMonitor.onHoldReleased = { [weak self] in
    self?.zoomManager.collapseFocusedWindow()
}
zoomToggleMonitor.start()
```

In the permission timer block (around line 53), after `self.gestureMonitor.start()`, add:

```swift
if !self.zoomToggleMonitor.isRunning {
    self.zoomToggleMonitor.start()
}
```

**Step 2: Clear zoom state when window is re-tiled via gesture**

In `Sources/Swipey/GestureMonitor.swift`:

Add a new property after `onGestureCancelled` (line 26):

```swift
/// Called when a window is about to be tiled (so zoom state can be cleared).
var onWindowTiled: ((AXUIElement) -> Void)?
```

In `handleEnded()`, just before the `windowManager.tile(...)` call (line 285), add:

```swift
onWindowTiled?(window)
```

Also in `handleEnded()`, just before the `windowManager.exitFullscreenAndTile(...)` call (line 273), add:

```swift
onWindowTiled?(window)
```

**Step 3: Connect the callback in AppDelegate**

In `applicationDidFinishLaunching`, after the `gestureMonitor.onGestureCancelled` block, add:

```swift
gestureMonitor.onWindowTiled = { [weak self] window in
    self?.zoomManager.clearZoomState(for: window)
}
```

**Step 4: Build and verify**

Run: `cd /Users/omarmaroki/Projects/swipey && swift build 2>&1`
Expected: Build succeeds

**Step 5: Run all tests**

Run: `cd /Users/omarmaroki/Projects/swipey && swift test 2>&1`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/Swipey/AppDelegate.swift Sources/Swipey/GestureMonitor.swift
git commit -m "feat: wire up zoom toggle in AppDelegate and clear zoom on re-tile"
```

---

### Task 7: Manual Integration Test

**Files:** None (testing only)

**Step 1: Build and run the app**

Run: `cd /Users/omarmaroki/Projects/swipey && swift build && .build/debug/Swipey &`

**Step 2: Manual test checklist**

1. Tile a window to a quarter position using trackpad gesture
2. Tap left Cmd then right Cmd quickly → window should expand ~50% anchored to corner
3. Tap left Cmd then right Cmd again → window should snap back to tile
4. Tile a window and do the double-Cmd, but hold the second key briefly (<0.5s) and release → window should expand then snap back on release
5. Tile a window and do double-Cmd, hold second key for >0.5s → window stays expanded after release (toggle mode)
6. While zoomed, re-tile the window via trackpad gesture → zoom state should clear
7. Try double-Cmd on a non-tiled window → nothing should happen
8. Try Cmd+C, Cmd+V → should NOT trigger zoom (non-modifier key resets sequence)

**Step 3: Kill the test instance**

Run: `killall Swipey`

**Step 4: Final commit with any fixes**

If any fixes were needed, commit them:

```bash
git add -A && git commit -m "fix: address issues found in manual testing"
```
