# Grid Resize Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to hold Ctrl while dragging a window edge to resize adjacent tiled windows along shared edges, maintaining the grid layout.

**Architecture:** A `GridResizeManager` monitors Ctrl key state via CGEventTap. On Ctrl press, it snapshots all tiled windows on the active screen, identifies shared edges between them, and starts a 60Hz polling timer. Each poll detects frame changes and propagates them to adjacent windows. On Ctrl release, everything is discarded. A pure `GridSnapshot` struct handles edge detection logic and is fully unit-testable.

**Tech Stack:** Swift 6, CGEventTap (flagsChanged), AXUIElement, DispatchSourceTimer, Swift Testing framework

**Design doc:** `docs/plans/2026-02-13-grid-resize-design.md`

---

### Task 1: GridSnapshot — Data Types and Edge Detection (Pure Logic)

This is the testable core. All coordinate math, no AXUIElement dependencies.

**Files:**
- Create: `Sources/Swipey/GridSnapshot.swift`
- Create: `Tests/SwipeyTests/GridSnapshotTests.swift`

**Step 1: Write the failing tests**

In `Tests/SwipeyTests/GridSnapshotTests.swift`:

```swift
import Testing
@testable import SwipeyLib

@Suite("GridSnapshot Tests")
struct GridSnapshotTests {

    // Mock a 1440x900 visible frame at origin (0,0) — CG coordinates (top-left origin)
    let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // Two halves side by side (CG coords, top-left origin)
    // Left half:  (2, 0, 716, 896) — 2pt margin, full height minus 2*margin
    // Right half: (722, 0, 716, 896) — after 4pt gap
    let leftHalf  = CGRect(x: 2, y: 2, width: 716, height: 896)
    let rightHalf = CGRect(x: 722, y: 2, width: 716, height: 896)

    // Four quarters (CG coords)
    let topLeft     = CGRect(x: 2, y: 2, width: 716, height: 446)
    let topRight    = CGRect(x: 722, y: 2, width: 716, height: 446)
    let bottomLeft  = CGRect(x: 2, y: 452, width: 716, height: 446)
    let bottomRight = CGRect(x: 722, y: 452, width: 716, height: 446)

    @Test("Two halves produce one vertical shared edge")
    func twoHalvesSharedEdge() {
        let windows: [(id: Int, frame: CGRect)] = [
            (id: 1, frame: leftHalf),
            (id: 2, frame: rightHalf),
        ]
        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        #expect(snapshot.sharedEdges.count == 1)

        let edge = snapshot.sharedEdges[0]
        #expect(edge.axis == .vertical)
        // The shared edge coordinate should be between the right edge of left (718) and left edge of right (722)
        #expect(edge.windowAId == 1)
        #expect(edge.windowBId == 2)
    }

    @Test("Four quarters produce 4 shared edges")
    func fourQuartersSharedEdges() {
        let windows: [(id: Int, frame: CGRect)] = [
            (id: 1, frame: topLeft),
            (id: 2, frame: topRight),
            (id: 3, frame: bottomLeft),
            (id: 4, frame: bottomRight),
        ]
        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        // Vertical edges: topLeft-topRight, bottomLeft-bottomRight
        // Horizontal edges: topLeft-bottomLeft, topRight-bottomRight
        #expect(snapshot.sharedEdges.count == 4)

        let verticalEdges = snapshot.sharedEdges.filter { $0.axis == .vertical }
        let horizontalEdges = snapshot.sharedEdges.filter { $0.axis == .horizontal }
        #expect(verticalEdges.count == 2)
        #expect(horizontalEdges.count == 2)
    }

    @Test("No shared edge for non-adjacent windows")
    func nonAdjacentWindows() {
        // Two windows on opposite corners with a gap
        let windows: [(id: Int, frame: CGRect)] = [
            (id: 1, frame: topLeft),
            (id: 2, frame: bottomRight),
        ]
        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        #expect(snapshot.sharedEdges.isEmpty)
    }

    @Test("Single window produces no shared edges")
    func singleWindow() {
        let windows: [(id: Int, frame: CGRect)] = [
            (id: 1, frame: leftHalf),
        ]
        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        #expect(snapshot.sharedEdges.isEmpty)
    }

    @Test("findAffectedEdges returns correct edges for a window")
    func findAffectedEdgesForWindow() {
        let windows: [(id: Int, frame: CGRect)] = [
            (id: 1, frame: leftHalf),
            (id: 2, frame: rightHalf),
        ]
        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        let edges = snapshot.findAffectedEdges(forWindow: 1, movedEdge: .right)
        #expect(edges.count == 1)
        #expect(edges[0].axis == .vertical)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: Compilation errors — `GridSnapshot` doesn't exist yet.

**Step 3: Write minimal implementation**

In `Sources/Swipey/GridSnapshot.swift`:

```swift
import Foundation

enum SharedEdgeAxis: Sendable {
    case vertical    // shared x-coordinate (left/right adjacency)
    case horizontal  // shared y-coordinate (top/bottom adjacency)
}

enum WindowEdgeSide: Sendable {
    case left, right, top, bottom
}

struct SharedEdge: Sendable {
    let windowAId: Int
    let windowBId: Int
    let axis: SharedEdgeAxis
    /// The coordinate of the shared edge (midpoint between the two edges).
    let coordinate: CGFloat
    /// The overlapping range on the perpendicular axis.
    let spanStart: CGFloat
    let spanEnd: CGFloat
}

struct GridSnapshot: Sendable {
    struct WindowEntry: Sendable {
        let id: Int
        var frame: CGRect
        var isAdjusting: Bool = false
    }

    private(set) var windows: [WindowEntry]
    let sharedEdges: [SharedEdge]
    let screenFrame: CGRect

    private static let edgeTolerance: CGFloat = 6
    private static let overlapThreshold: CGFloat = 10

    init(windows: [(id: Int, frame: CGRect)], screenFrame: CGRect) {
        self.screenFrame = screenFrame
        self.windows = windows.map { WindowEntry(id: $0.id, frame: $0.frame) }
        self.sharedEdges = Self.detectSharedEdges(
            windows: self.windows,
            tolerance: Self.edgeTolerance,
            overlapThreshold: Self.overlapThreshold
        )
    }

    /// Find shared edges affected when a specific window's edge moves.
    func findAffectedEdges(forWindow windowId: Int, movedEdge: WindowEdgeSide) -> [SharedEdge] {
        return sharedEdges.filter { edge in
            switch movedEdge {
            case .right:
                return edge.axis == .vertical && edge.windowAId == windowId
            case .left:
                return edge.axis == .vertical && edge.windowBId == windowId
            case .bottom:
                return edge.axis == .horizontal && edge.windowAId == windowId
            case .top:
                return edge.axis == .horizontal && edge.windowBId == windowId
            }
        }
    }

    /// Update a window's frame in the snapshot. Returns the old frame.
    @discardableResult
    mutating func updateFrame(forWindow windowId: Int, newFrame: CGRect) -> CGRect? {
        guard let index = windows.firstIndex(where: { $0.id == windowId }) else { return nil }
        let old = windows[index].frame
        windows[index].frame = newFrame
        return old
    }

    mutating func setAdjusting(_ adjusting: Bool, forWindow windowId: Int) {
        guard let index = windows.firstIndex(where: { $0.id == windowId }) else { return }
        windows[index].isAdjusting = adjusting
    }

    func isAdjusting(windowId: Int) -> Bool {
        return windows.first(where: { $0.id == windowId })?.isAdjusting ?? false
    }

    func entry(forWindow windowId: Int) -> WindowEntry? {
        return windows.first(where: { $0.id == windowId })
    }

    // MARK: - Edge Detection

    private static func detectSharedEdges(
        windows: [WindowEntry],
        tolerance: CGFloat,
        overlapThreshold: CGFloat
    ) -> [SharedEdge] {
        var edges: [SharedEdge] = []

        for i in 0..<windows.count {
            for j in (i + 1)..<windows.count {
                let a = windows[i]
                let b = windows[j]

                // Check vertical shared edge: A's right edge ~ B's left edge
                if abs(a.frame.maxX - b.frame.minX) <= tolerance {
                    let overlapStart = max(a.frame.minY, b.frame.minY)
                    let overlapEnd = min(a.frame.maxY, b.frame.maxY)
                    if overlapEnd - overlapStart >= overlapThreshold {
                        edges.append(SharedEdge(
                            windowAId: a.id,
                            windowBId: b.id,
                            axis: .vertical,
                            coordinate: (a.frame.maxX + b.frame.minX) / 2,
                            spanStart: overlapStart,
                            spanEnd: overlapEnd
                        ))
                    }
                }
                // Check vertical shared edge: B's right edge ~ A's left edge
                else if abs(b.frame.maxX - a.frame.minX) <= tolerance {
                    let overlapStart = max(a.frame.minY, b.frame.minY)
                    let overlapEnd = min(a.frame.maxY, b.frame.maxY)
                    if overlapEnd - overlapStart >= overlapThreshold {
                        edges.append(SharedEdge(
                            windowAId: b.id,
                            windowBId: a.id,
                            axis: .vertical,
                            coordinate: (b.frame.maxX + a.frame.minX) / 2,
                            spanStart: overlapStart,
                            spanEnd: overlapEnd
                        ))
                    }
                }

                // Check horizontal shared edge: A's bottom edge ~ B's top edge
                if abs(a.frame.maxY - b.frame.minY) <= tolerance {
                    let overlapStart = max(a.frame.minX, b.frame.minX)
                    let overlapEnd = min(a.frame.maxX, b.frame.maxX)
                    if overlapEnd - overlapStart >= overlapThreshold {
                        edges.append(SharedEdge(
                            windowAId: a.id,
                            windowBId: b.id,
                            axis: .horizontal,
                            coordinate: (a.frame.maxY + b.frame.minY) / 2,
                            spanStart: overlapStart,
                            spanEnd: overlapEnd
                        ))
                    }
                }
                // Check horizontal shared edge: B's bottom edge ~ A's top edge
                else if abs(b.frame.maxY - a.frame.minY) <= tolerance {
                    let overlapStart = max(a.frame.minX, b.frame.minX)
                    let overlapEnd = min(a.frame.maxX, b.frame.maxX)
                    if overlapEnd - overlapStart >= overlapThreshold {
                        edges.append(SharedEdge(
                            windowAId: b.id,
                            windowBId: a.id,
                            axis: .horizontal,
                            coordinate: (b.frame.maxY + a.frame.minY) / 2,
                            spanStart: overlapStart,
                            spanEnd: overlapEnd
                        ))
                    }
                }
            }
        }

        return edges
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: All 5 tests pass.

**Step 5: Commit**

```bash
git add Sources/Swipey/GridSnapshot.swift Tests/SwipeyTests/GridSnapshotTests.swift
git commit -m "feat: add GridSnapshot with shared edge detection and tests"
```

---

### Task 2: Edge Propagation Logic (Pure Logic)

Add a function that computes the new frame for an adjacent window when a shared edge moves.

**Files:**
- Modify: `Sources/Swipey/GridSnapshot.swift`
- Modify: `Tests/SwipeyTests/GridSnapshotTests.swift`

**Step 1: Write the failing tests**

Append to `Tests/SwipeyTests/GridSnapshotTests.swift`:

```swift
@Test("Propagation: right edge of left-half moves right, left edge of right-half follows")
func propagateVerticalEdge() {
    var snapshot = GridSnapshot(
        windows: [(id: 1, frame: leftHalf), (id: 2, frame: rightHalf)],
        screenFrame: screenFrame
    )
    // Simulate left-half's right edge moving +50pt (user dragged it)
    let newLeftFrame = CGRect(
        x: leftHalf.origin.x,
        y: leftHalf.origin.y,
        width: leftHalf.width + 50,
        height: leftHalf.height
    )
    snapshot.updateFrame(forWindow: 1, newFrame: newLeftFrame)

    let adjustments = snapshot.computePropagation(
        changedWindowId: 1,
        oldFrame: leftHalf,
        newFrame: newLeftFrame
    )

    #expect(adjustments.count == 1)
    #expect(adjustments[0].windowId == 2)
    // Right-half's left edge should move +50, so x increases by 50 and width decreases by 50
    #expect(abs(adjustments[0].newFrame.origin.x - (rightHalf.origin.x + 50)) < 1)
    #expect(abs(adjustments[0].newFrame.width - (rightHalf.width - 50)) < 1)
    // Height and y unchanged
    #expect(abs(adjustments[0].newFrame.origin.y - rightHalf.origin.y) < 1)
    #expect(abs(adjustments[0].newFrame.height - rightHalf.height) < 1)
}

@Test("Propagation: bottom edge of top-left moves down, top edge of bottom-left follows")
func propagateHorizontalEdge() {
    var snapshot = GridSnapshot(
        windows: [
            (id: 1, frame: topLeft),
            (id: 2, frame: topRight),
            (id: 3, frame: bottomLeft),
            (id: 4, frame: bottomRight),
        ],
        screenFrame: screenFrame
    )
    // Top-left's bottom edge moves down 30pt
    let newTopLeft = CGRect(
        x: topLeft.origin.x,
        y: topLeft.origin.y,
        width: topLeft.width,
        height: topLeft.height + 30
    )
    snapshot.updateFrame(forWindow: 1, newFrame: newTopLeft)

    let adjustments = snapshot.computePropagation(
        changedWindowId: 1,
        oldFrame: topLeft,
        newFrame: newTopLeft
    )

    // Should affect bottom-left (shares horizontal edge)
    #expect(adjustments.count == 1)
    let adj = adjustments[0]
    #expect(adj.windowId == 3)
    // Bottom-left's top edge moves down 30pt
    #expect(abs(adj.newFrame.origin.y - (bottomLeft.origin.y + 30)) < 1)
    #expect(abs(adj.newFrame.height - (bottomLeft.height - 30)) < 1)
}

@Test("No propagation for window marked as adjusting")
func noPropagationForAdjusting() {
    var snapshot = GridSnapshot(
        windows: [(id: 1, frame: leftHalf), (id: 2, frame: rightHalf)],
        screenFrame: screenFrame
    )
    snapshot.setAdjusting(true, forWindow: 1)

    let newLeftFrame = CGRect(
        x: leftHalf.origin.x,
        y: leftHalf.origin.y,
        width: leftHalf.width + 50,
        height: leftHalf.height
    )

    let adjustments = snapshot.computePropagation(
        changedWindowId: 1,
        oldFrame: leftHalf,
        newFrame: newLeftFrame
    )

    #expect(adjustments.isEmpty)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: Compilation error — `computePropagation` doesn't exist.

**Step 3: Write minimal implementation**

Add to `GridSnapshot` in `Sources/Swipey/GridSnapshot.swift`:

```swift
struct FrameAdjustment: Sendable {
    let windowId: Int
    let newFrame: CGRect
}

/// Given a window whose frame changed, compute the adjustments needed for adjacent windows.
func computePropagation(
    changedWindowId: Int,
    oldFrame: CGRect,
    newFrame: CGRect
) -> [FrameAdjustment] {
    // Don't propagate changes from windows we adjusted ourselves
    if isAdjusting(windowId: changedWindowId) { return [] }

    var adjustments: [FrameAdjustment] = []

    // Check each edge for movement
    let leftDelta = newFrame.minX - oldFrame.minX
    let rightDelta = newFrame.maxX - oldFrame.maxX
    let topDelta = newFrame.minY - oldFrame.minY
    let bottomDelta = newFrame.maxY - oldFrame.maxY

    // Right edge moved → affects vertical shared edges where this window is A
    if abs(rightDelta) > 0.5 {
        for edge in sharedEdges where edge.axis == .vertical && edge.windowAId == changedWindowId {
            if let neighbor = entry(forWindow: edge.windowBId) {
                let adjusted = CGRect(
                    x: neighbor.frame.origin.x + rightDelta,
                    y: neighbor.frame.origin.y,
                    width: neighbor.frame.width - rightDelta,
                    height: neighbor.frame.height
                )
                adjustments.append(FrameAdjustment(windowId: edge.windowBId, newFrame: adjusted))
            }
        }
    }

    // Left edge moved → affects vertical shared edges where this window is B
    if abs(leftDelta) > 0.5 {
        for edge in sharedEdges where edge.axis == .vertical && edge.windowBId == changedWindowId {
            if let neighbor = entry(forWindow: edge.windowAId) {
                let adjusted = CGRect(
                    x: neighbor.frame.origin.x,
                    y: neighbor.frame.origin.y,
                    width: neighbor.frame.width + leftDelta,
                    height: neighbor.frame.height
                )
                adjustments.append(FrameAdjustment(windowId: edge.windowAId, newFrame: adjusted))
            }
        }
    }

    // Bottom edge moved → affects horizontal shared edges where this window is A
    if abs(bottomDelta) > 0.5 {
        for edge in sharedEdges where edge.axis == .horizontal && edge.windowAId == changedWindowId {
            if let neighbor = entry(forWindow: edge.windowBId) {
                let adjusted = CGRect(
                    x: neighbor.frame.origin.x,
                    y: neighbor.frame.origin.y + bottomDelta,
                    width: neighbor.frame.width,
                    height: neighbor.frame.height - bottomDelta
                )
                adjustments.append(FrameAdjustment(windowId: edge.windowBId, newFrame: adjusted))
            }
        }
    }

    // Top edge moved → affects horizontal shared edges where this window is B
    if abs(topDelta) > 0.5 {
        for edge in sharedEdges where edge.axis == .horizontal && edge.windowBId == changedWindowId {
            if let neighbor = entry(forWindow: edge.windowAId) {
                let adjusted = CGRect(
                    x: neighbor.frame.origin.x,
                    y: neighbor.frame.origin.y,
                    width: neighbor.frame.width,
                    height: neighbor.frame.height + topDelta
                )
                adjustments.append(FrameAdjustment(windowId: edge.windowAId, newFrame: adjusted))
            }
        }
    }

    return adjustments
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: All 8 tests pass.

**Step 5: Commit**

```bash
git add Sources/Swipey/GridSnapshot.swift Tests/SwipeyTests/GridSnapshotTests.swift
git commit -m "feat: add edge propagation logic to GridSnapshot"
```

---

### Task 3: GridResizeManager — Ctrl Key Monitoring

The event tap that watches for Ctrl press/release. No polling yet — just the key monitoring skeleton.

**Files:**
- Create: `Sources/Swipey/GridResizeManager.swift`

**Step 1: Write GridResizeManager with Ctrl key monitoring**

In `Sources/Swipey/GridResizeManager.swift`:

```swift
@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "grid-resize")

final class GridResizeManager: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: DispatchSourceTimer?
    private var snapshot: GridSnapshot?
    private var windowElements: [Int: AXUIElement] = [:]  // window id -> AXUIElement

    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<GridResizeManager>.fromOpaque(userInfo).takeUnretainedValue()
            manager.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)  // never consume — pass through
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create grid resize event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("[Swipey] Grid resize monitor started")
    }

    func stop() {
        stopPolling()
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

        guard type == .flagsChanged else { return }

        let flags = event.flags
        if flags.contains(.maskControl) {
            // Ctrl pressed — build snapshot and start polling
            if snapshot == nil {
                startGridSession()
            }
        } else {
            // Ctrl released — stop polling
            if snapshot != nil {
                stopPolling()
            }
        }
    }

    // MARK: - Grid Session

    private func startGridSession() {
        let windows = discoverTiledWindows()
        guard windows.count >= 2 else {
            logger.debug("[Swipey] Grid resize: fewer than 2 tiled windows, skipping")
            return
        }

        // Get screen frame for the screen under the cursor
        let mouseLocation = NSEvent.mouseLocation
        guard let mainScreen = NSScreen.screens.first else { return }
        let cgMouseY = mainScreen.frame.height - mouseLocation.y
        let cgMouse = CGPoint(x: mouseLocation.x, y: cgMouseY)

        let screen = NSScreen.screens.first(where: { screen in
            let cgScreenOrigin = CGPoint(x: screen.frame.origin.x, y: mainScreen.frame.height - screen.frame.maxY)
            let cgScreenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)
            return cgScreenFrame.contains(cgMouse)
        }) ?? mainScreen

        let cgScreenOrigin = CGPoint(x: screen.frame.origin.x, y: mainScreen.frame.height - screen.frame.maxY)
        let screenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)

        var windowEntries: [(id: Int, frame: CGRect)] = []
        windowElements = [:]
        for (axElement, frame) in windows {
            let key = Int(CFHash(axElement))
            windowEntries.append((id: key, frame: frame))
            windowElements[key] = axElement
        }

        snapshot = GridSnapshot(windows: windowEntries, screenFrame: screenFrame)

        guard let snap = snapshot, !snap.sharedEdges.isEmpty else {
            logger.debug("[Swipey] Grid resize: no shared edges found")
            snapshot = nil
            windowElements = [:]
            return
        }

        logger.info("[Swipey] Grid resize: found \(snap.sharedEdges.count) shared edge(s) across \(snap.windows.count) windows")
        startPolling()
    }

    // MARK: - Window Discovery

    /// Find all windows on screen and return their AXUIElement + CG frame.
    private func discoverTiledWindows() -> [(AXUIElement, CGRect)] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [(AXUIElement, CGRect)] = []

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0  // normal window layer only
            else { continue }

            guard let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }

            let frame = CGRect(x: x, y: y, width: w, height: h)

            // Skip tiny windows (menu bar items, etc.)
            guard w > 100 && h > 100 else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

            // Match CG window bounds to AX window
            for axWindow in axWindows {
                if let axFrame = getFrame(of: axWindow),
                   abs(axFrame.origin.x - x) < 2 && abs(axFrame.origin.y - y) < 2 &&
                   abs(axFrame.width - w) < 2 && abs(axFrame.height - h) < 2 {
                    results.append((axWindow, frame))
                    break
                }
            }
        }

        return results
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))  // ~60Hz
        timer.setEventHandler { [weak self] in
            self?.pollWindowFrames()
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
        snapshot = nil
        windowElements = [:]
        logger.debug("[Swipey] Grid resize: session ended")
    }

    private func pollWindowFrames() {
        guard var snap = snapshot else { return }

        // Clear adjusting flags from previous cycle
        for entry in snap.windows {
            if entry.isAdjusting {
                snap.setAdjusting(false, forWindow: entry.id)
            }
        }

        for entry in snap.windows {
            guard let axElement = windowElements[entry.id],
                  let currentFrame = getFrame(of: axElement) else {
                // Window gone — remove it
                continue
            }

            let oldFrame = entry.frame
            guard !framesEqual(oldFrame, currentFrame) else { continue }

            // Frame changed
            snap.updateFrame(forWindow: entry.id, newFrame: currentFrame)

            if entry.isAdjusting {
                // This was our own adjustment — skip propagation
                continue
            }

            let adjustments = snap.computePropagation(
                changedWindowId: entry.id,
                oldFrame: oldFrame,
                newFrame: currentFrame
            )

            for adj in adjustments {
                guard let adjElement = windowElements[adj.windowId] else { continue }
                setFrame(of: adjElement, to: adj.newFrame)
                snap.updateFrame(forWindow: adj.windowId, newFrame: adj.newFrame)
                snap.setAdjusting(true, forWindow: adj.windowId)
            }
        }

        snapshot = snap
    }

    // MARK: - AX Helpers

    private func getFrame(of window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              let axPos = posValue as! AXValue? else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axPos, .cgPoint, &point) else { return nil }

        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let axSize = sizeValue as! AXValue? else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axSize, .cgSize, &size) else { return nil }

        return CGRect(origin: point, size: size)
    }

    private func setFrame(of window: AXUIElement, to frame: CGRect) {
        var point = frame.origin
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func framesEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.origin.x - b.origin.x) < 0.5
            && abs(a.origin.y - b.origin.y) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    deinit {
        stop()
    }
}
```

**Step 2: Build to verify compilation**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 3: Commit**

```bash
git add Sources/Swipey/GridResizeManager.swift
git commit -m "feat: add GridResizeManager with Ctrl key monitoring and poll loop"
```

---

### Task 4: Wire Into AppDelegate

**Files:**
- Modify: `Sources/Swipey/AppDelegate.swift:7-20` (add property)
- Modify: `Sources/Swipey/AppDelegate.swift:46-48` (create and start)
- Modify: `Sources/Swipey/AppDelegate.swift:82-83` (re-enable check in permission timer)

**Step 1: Add property**

In `AppDelegate.swift`, after line 20 (`private var zoomManager: ZoomManager!`), add:

```swift
private var gridResizeManager: GridResizeManager!
```

**Step 2: Create and start in applicationDidFinishLaunching**

After the `zoomToggleMonitor.start()` line (line 47), add:

```swift
gridResizeManager = GridResizeManager()
gridResizeManager.start()
```

**Step 3: Add re-enable check in permission timer**

After the `zoomToggleMonitor` re-enable block (around line 83), add:

```swift
if self.accessibilityManager.isTrusted && !self.gridResizeManager.isRunning {
    self.gridResizeManager.start()
}
```

**Step 4: Build to verify compilation**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 5: Commit**

```bash
git add Sources/Swipey/AppDelegate.swift
git commit -m "feat: wire GridResizeManager into AppDelegate lifecycle"
```

---

### Task 5: Manual Integration Test

No automated test for the full integration (requires live accessibility + multiple windows). Verify manually.

**Step 1: Build and run**

Run: `swift build && .build/debug/Swipey &`

**Step 2: Test with two halves**

1. Open two windows (e.g. two Finder windows)
2. Swipe one left-half, the other right-half
3. Hold Ctrl, drag the inner edge of one window
4. Verify the adjacent window resizes to match
5. Release Ctrl — verify normal resize behavior returns

**Step 3: Test with four quarters**

1. Tile four windows into quarters
2. Hold Ctrl, drag a center edge
3. Verify all windows along that edge adjust

**Step 4: Test edge cases**

- Close a window while Ctrl held — no crash
- Hold Ctrl with only one tiled window — nothing happens
- Hold Ctrl with no tiled windows — nothing happens

**Step 5: Kill the test process**

Run: `killall Swipey`

**Step 6: Commit any fixes needed, then final commit**

```bash
git add -A
git commit -m "feat: grid resize — Ctrl+drag resizes adjacent tiled windows"
```
