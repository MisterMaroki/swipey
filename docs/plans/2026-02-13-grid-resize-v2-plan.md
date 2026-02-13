# Grid Resize v2 — Hover Handle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When Swipey tiles windows, shared edges get a drag handle that appears on hover, letting users resize both windows simultaneously — like native macOS tiling.

**Architecture:** A `TileRegistry` (inside `EdgeHandleController`) tracks which windows are tiled. When entries change, `GridSnapshot` recomputes shared edges, collinear edges are grouped into `EdgeGroup`s, and an `NSPanel` with an `EdgeHandleView` is placed over each group. The view handles hover (highlight + cursor) and drag (AX resize) natively via AppKit — no event taps or polling needed.

**Tech Stack:** Swift 6, NSPanel, NSTrackingArea, AXUIElement, GridSnapshot (existing)

**Design doc:** `docs/plans/2026-02-13-grid-resize-v2-design.md`

---

### Task 1: Delete GridResizeManager and Unwire from AppDelegate

**Files:**
- Delete: `Sources/Swipey/GridResizeManager.swift`
- Modify: `Sources/Swipey/AppDelegate.swift`

**Step 1: Delete GridResizeManager.swift**

Delete the file `Sources/Swipey/GridResizeManager.swift`.

**Step 2: Remove from AppDelegate**

In `Sources/Swipey/AppDelegate.swift`, remove:
- The property `private var gridResizeManager: GridResizeManager!`
- The two lines in `applicationDidFinishLaunching`: `gridResizeManager = GridResizeManager()` and `gridResizeManager.start()`
- The re-enable block in the permission timer: the `if self.accessibilityManager.isTrusted && !self.gridResizeManager.isRunning { self.gridResizeManager.start() }` block

**Step 3: Build to verify**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 4: Run tests**

Run: `swift test 2>&1`
Expected: All tests pass (GridSnapshot tests still work since GridSnapshot.swift is unchanged).

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove GridResizeManager (Ctrl key approach)"
```

---

### Task 2: Add EdgeGroup to GridSnapshot (Pure Logic + Tests)

Group collinear shared edges into single handle units, and add a helper to compute the NSPanel frame.

**Files:**
- Modify: `Sources/Swipey/GridSnapshot.swift`
- Modify: `Tests/SwipeyTests/GridSnapshotTests.swift`

**Step 1: Write the failing tests**

Append to `Tests/SwipeyTests/GridSnapshotTests.swift`, inside the `GridSnapshotTests` struct:

```swift
// MARK: - Edge Grouping

@Test("Two halves produce 1 edge group")
func twoHalvesOneGroup() {
    let snapshot = GridSnapshot(
        windows: [(id: 1, frame: leftHalf), (id: 2, frame: rightHalf)],
        screenFrame: screenFrame
    )
    let groups = EdgeGroup.fromEdges(snapshot.sharedEdges)
    #expect(groups.count == 1)
    #expect(groups[0].axis == .vertical)
    #expect(groups[0].edges.count == 1)
}

@Test("Four quarters produce 2 edge groups")
func fourQuartersTwoGroups() {
    let snapshot = GridSnapshot(
        windows: [
            (id: 1, frame: topLeft),
            (id: 2, frame: topRight),
            (id: 3, frame: bottomLeft),
            (id: 4, frame: bottomRight),
        ],
        screenFrame: screenFrame
    )
    let groups = EdgeGroup.fromEdges(snapshot.sharedEdges)
    #expect(groups.count == 2)
    let vertical = groups.filter { $0.axis == .vertical }
    let horizontal = groups.filter { $0.axis == .horizontal }
    #expect(vertical.count == 1)
    #expect(horizontal.count == 1)
    // Vertical group merges TL-TR and BL-BR edges
    #expect(vertical[0].edges.count == 2)
    // Horizontal group merges TL-BL and TR-BR edges
    #expect(horizontal[0].edges.count == 2)
}

@Test("Vertical group spans full height for four quarters")
func fourQuartersVerticalGroupSpan() {
    let snapshot = GridSnapshot(
        windows: [
            (id: 1, frame: topLeft),
            (id: 2, frame: topRight),
            (id: 3, frame: bottomLeft),
            (id: 4, frame: bottomRight),
        ],
        screenFrame: screenFrame
    )
    let groups = EdgeGroup.fromEdges(snapshot.sharedEdges)
    let vertical = groups.first { $0.axis == .vertical }!
    // Union of TL-TR span (2..448) and BL-BR span (452..898)
    #expect(vertical.spanStart == 2)
    #expect(vertical.spanEnd == 898)
}

@Test("panelFrame converts vertical CG edge to NS rect")
func panelFrameVertical() {
    let group = EdgeGroup(
        axis: .vertical,
        coordinate: 720,
        spanStart: 2,
        spanEnd: 898,
        edges: []
    )
    let nsFrame = group.panelFrame(mainScreenHeight: 900, handleWidth: 8)
    #expect(nsFrame.origin.x == 716)  // 720 - 4
    #expect(nsFrame.width == 8)
    #expect(abs(nsFrame.origin.y - 2) < 1)  // 900 - 898
    #expect(abs(nsFrame.height - 896) < 1)  // 898 - 2
}

@Test("panelFrame converts horizontal CG edge to NS rect")
func panelFrameHorizontal() {
    let group = EdgeGroup(
        axis: .horizontal,
        coordinate: 450,
        spanStart: 2,
        spanEnd: 1438,
        edges: []
    )
    let nsFrame = group.panelFrame(mainScreenHeight: 900, handleWidth: 8)
    #expect(nsFrame.origin.x == 2)
    #expect(abs(nsFrame.width - 1436) < 1)
    #expect(abs(nsFrame.origin.y - 446) < 1)  // 900 - 450 - 4
    #expect(nsFrame.height == 8)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: Compilation error — `EdgeGroup` doesn't exist.

**Step 3: Write implementation**

Add to the bottom of `Sources/Swipey/GridSnapshot.swift`, outside the `GridSnapshot` struct:

```swift
struct EdgeGroup: Sendable {
    let axis: SharedEdgeAxis
    let coordinate: CGFloat
    let spanStart: CGFloat
    let spanEnd: CGFloat
    let edges: [SharedEdge]

    /// Collect unique window IDs on side A (left/top).
    var sideAWindowIds: Set<Int> {
        Set(edges.map(\.windowAId))
    }

    /// Collect unique window IDs on side B (right/bottom).
    var sideBWindowIds: Set<Int> {
        Set(edges.map(\.windowBId))
    }

    /// Group collinear shared edges (same axis, coordinate within tolerance) into EdgeGroups.
    static func fromEdges(_ edges: [SharedEdge], tolerance: CGFloat = 6) -> [EdgeGroup] {
        var groups: [EdgeGroup] = []
        var used = Set<Int>()

        for (i, edge) in edges.enumerated() {
            guard !used.contains(i) else { continue }
            used.insert(i)

            var grouped = [edge]
            var spanStart = edge.spanStart
            var spanEnd = edge.spanEnd

            for (j, other) in edges.enumerated() where j > i && !used.contains(j) {
                if other.axis == edge.axis && abs(other.coordinate - edge.coordinate) <= tolerance {
                    grouped.append(other)
                    spanStart = min(spanStart, other.spanStart)
                    spanEnd = max(spanEnd, other.spanEnd)
                    used.insert(j)
                }
            }

            groups.append(EdgeGroup(
                axis: edge.axis,
                coordinate: edge.coordinate,
                spanStart: spanStart,
                spanEnd: spanEnd,
                edges: grouped
            ))
        }

        return groups
    }

    /// Compute the NSPanel frame for this edge group (NS coordinates, bottom-left origin).
    func panelFrame(mainScreenHeight: CGFloat, handleWidth: CGFloat = 8) -> CGRect {
        let halfWidth = handleWidth / 2
        if axis == .vertical {
            return CGRect(
                x: coordinate - halfWidth,
                y: mainScreenHeight - spanEnd,
                width: handleWidth,
                height: spanEnd - spanStart
            )
        } else {
            return CGRect(
                x: spanStart,
                y: mainScreenHeight - coordinate - halfWidth,
                width: spanEnd - spanStart,
                height: handleWidth
            )
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter GridSnapshotTests 2>&1`
Expected: All 13 tests pass.

**Step 5: Commit**

```bash
git add Sources/Swipey/GridSnapshot.swift Tests/SwipeyTests/GridSnapshotTests.swift
git commit -m "feat: add EdgeGroup with collinear edge grouping and panel frame conversion"
```

---

### Task 3: EdgeHandleView — Hover and Drag

The NSView that handles mouse interaction: hover shows a highlight line + resize cursor, drag resizes adjacent windows via AXUIElement.

**Files:**
- Create: `Sources/Swipey/EdgeHandleView.swift`

**Step 1: Write EdgeHandleView**

In `Sources/Swipey/EdgeHandleView.swift`:

```swift
@preconcurrency import ApplicationServices
import AppKit

final class EdgeHandleView: NSView {
    struct WindowSide {
        let key: Int
        let element: AXUIElement
        var initialFrame: CGRect = .zero
    }

    var axis: SharedEdgeAxis = .vertical
    var sideAWindows: [WindowSide] = []
    var sideBWindows: [WindowSide] = []
    var onDragEnded: (() -> Void)?

    private let highlightView = NSView()
    private var isDragging = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialPanelFrame: CGRect = .zero

    private static let minWindowSize: CGFloat = 200

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupHighlight()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHighlight()
    }

    private func setupHighlight() {
        highlightView.wantsLayer = true
        highlightView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        highlightView.isHidden = true
        addSubview(highlightView)
    }

    override func layout() {
        super.layout()
        if axis == .vertical {
            highlightView.frame = CGRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height)
        } else {
            highlightView.frame = CGRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 2)
        }
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        highlightView.isHidden = false
        let cursor: NSCursor = axis == .vertical ? .resizeLeftRight : .resizeUpDown
        cursor.push()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            highlightView.isHidden = true
            NSCursor.pop()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drag

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialPanelFrame = window?.frame ?? .zero
        isDragging = true

        // Snapshot current window frames
        for i in sideAWindows.indices {
            sideAWindows[i].initialFrame = getFrame(of: sideAWindows[i].element) ?? .zero
        }
        for i in sideBWindows.indices {
            sideBWindows[i].initialFrame = getFrame(of: sideBWindows[i].element) ?? .zero
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let current = NSEvent.mouseLocation
        let nsDeltaX = current.x - initialMouseLocation.x
        let nsDeltaY = current.y - initialMouseLocation.y

        // Compute CG delta for resize
        var delta: CGFloat
        if axis == .vertical {
            delta = nsDeltaX
        } else {
            delta = -nsDeltaY  // NS Y is inverted vs CG Y
        }

        // Clamp to minimum window size
        for item in sideAWindows {
            let dimension = axis == .vertical ? item.initialFrame.width : item.initialFrame.height
            delta = max(delta, -(dimension - Self.minWindowSize))
        }
        for item in sideBWindows {
            let dimension = axis == .vertical ? item.initialFrame.width : item.initialFrame.height
            delta = min(delta, dimension - Self.minWindowSize)
        }

        // Apply to side A (left/top): grow
        for item in sideAWindows {
            let f = item.initialFrame
            let newFrame: CGRect
            if axis == .vertical {
                newFrame = CGRect(x: f.origin.x, y: f.origin.y,
                                  width: f.width + delta, height: f.height)
            } else {
                newFrame = CGRect(x: f.origin.x, y: f.origin.y,
                                  width: f.width, height: f.height + delta)
            }
            setFrame(of: item.element, to: newFrame)
        }

        // Apply to side B (right/bottom): shrink
        for item in sideBWindows {
            let f = item.initialFrame
            let newFrame: CGRect
            if axis == .vertical {
                newFrame = CGRect(x: f.origin.x + delta, y: f.origin.y,
                                  width: f.width - delta, height: f.height)
            } else {
                newFrame = CGRect(x: f.origin.x, y: f.origin.y + delta,
                                  width: f.width, height: f.height - delta)
            }
            setFrame(of: item.element, to: newFrame)
        }

        // Move panel to follow drag
        if axis == .vertical {
            window?.setFrameOrigin(NSPoint(
                x: initialPanelFrame.origin.x + nsDeltaX,
                y: initialPanelFrame.origin.y
            ))
        } else {
            window?.setFrameOrigin(NSPoint(
                x: initialPanelFrame.origin.x,
                y: initialPanelFrame.origin.y + nsDeltaY
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        highlightView.isHidden = true
        NSCursor.pop()
        onDragEnded?()
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
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 3: Commit**

```bash
git add Sources/Swipey/EdgeHandleView.swift
git commit -m "feat: add EdgeHandleView with hover highlight and drag resize"
```

---

### Task 4: EdgeHandleController — Panel Lifecycle

Manages the tile registry and creates/removes NSPanels with EdgeHandleViews based on shared edges.

**Files:**
- Create: `Sources/Swipey/EdgeHandleController.swift`

**Step 1: Write EdgeHandleController**

In `Sources/Swipey/EdgeHandleController.swift`:

```swift
@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "edge-handle")

final class EdgeHandleController: @unchecked Sendable {
    struct TileEntry {
        let windowElement: AXUIElement
        let cgFrame: CGRect
        let screenFrame: CGRect
    }

    private var tiledWindows: [Int: TileEntry] = [:]
    private var panels: [NSPanel] = []
    private var pruneTimer: Timer?

    func registerTile(window: AXUIElement, position: TilePosition, screen: NSScreen) {
        guard position.needsFrame else { return }
        guard let mainScreen = NSScreen.screens.first else { return }

        let nsFrame = position.frame(for: screen)
        let cgOrigin = CGPoint(
            x: nsFrame.origin.x,
            y: mainScreen.frame.height - nsFrame.origin.y - nsFrame.height
        )
        let cgFrame = CGRect(origin: cgOrigin, size: nsFrame.size)
        let cgScreenOrigin = CGPoint(
            x: screen.frame.origin.x,
            y: mainScreen.frame.height - screen.frame.maxY
        )
        let screenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)

        let key = Int(CFHash(window))
        tiledWindows[key] = TileEntry(windowElement: window, cgFrame: cgFrame, screenFrame: screenFrame)
        rebuildHandles()
    }

    func unregisterTile(window: AXUIElement) {
        let key = Int(CFHash(window))
        tiledWindows.removeValue(forKey: key)
        rebuildHandles()
    }

    func start() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pruneStaleEntries()
        }
    }

    func stop() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        removeAllPanels()
    }

    // MARK: - Panel Management

    private func rebuildHandles() {
        removeAllPanels()

        let windows = tiledWindows.map { (id: $0.key, frame: $0.value.cgFrame) }
        guard let screenFrame = tiledWindows.values.first?.screenFrame else { return }
        guard let mainScreen = NSScreen.screens.first else { return }

        let snapshot = GridSnapshot(windows: windows, screenFrame: screenFrame)
        let groups = EdgeGroup.fromEdges(snapshot.sharedEdges)

        for group in groups {
            let nsFrame = group.panelFrame(mainScreenHeight: mainScreen.frame.height)
            let panel = createPanel(frame: nsFrame, group: group)
            panels.append(panel)
            panel.orderFrontRegardless()
        }

        logger.debug("[Swipey] Edge handles: \(groups.count) handle(s) for \(self.tiledWindows.count) tiled window(s)")
    }

    private func createPanel(frame: CGRect, group: EdgeGroup) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = EdgeHandleView(frame: NSRect(origin: .zero, size: frame.size))
        view.axis = group.axis
        view.autoresizingMask = [.width, .height]

        // Build window sides from the edge group
        var sideA: [EdgeHandleView.WindowSide] = []
        var sideB: [EdgeHandleView.WindowSide] = []
        for windowId in group.sideAWindowIds {
            if let entry = tiledWindows[windowId] {
                sideA.append(EdgeHandleView.WindowSide(key: windowId, element: entry.windowElement))
            }
        }
        for windowId in group.sideBWindowIds {
            if let entry = tiledWindows[windowId] {
                sideB.append(EdgeHandleView.WindowSide(key: windowId, element: entry.windowElement))
            }
        }
        view.sideAWindows = sideA
        view.sideBWindows = sideB

        view.onDragEnded = { [weak self] in
            self?.handleDragEnded()
        }

        panel.contentView = view
        return panel
    }

    private func removeAllPanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func handleDragEnded() {
        // Re-read actual frames from AX and update registry
        for (key, entry) in tiledWindows {
            if let currentFrame = getFrame(of: entry.windowElement) {
                tiledWindows[key] = TileEntry(
                    windowElement: entry.windowElement,
                    cgFrame: currentFrame,
                    screenFrame: entry.screenFrame
                )
            }
        }
        rebuildHandles()
    }

    // MARK: - Pruning

    private func pruneStaleEntries() {
        var keysToRemove: [Int] = []

        for (key, entry) in tiledWindows {
            guard let currentFrame = getFrame(of: entry.windowElement) else {
                // Window closed or inaccessible
                keysToRemove.append(key)
                continue
            }

            // Check if window moved away from tiled position
            let tolerance: CGFloat = 10
            if abs(currentFrame.origin.x - entry.cgFrame.origin.x) > tolerance ||
               abs(currentFrame.origin.y - entry.cgFrame.origin.y) > tolerance ||
               abs(currentFrame.width - entry.cgFrame.width) > tolerance ||
               abs(currentFrame.height - entry.cgFrame.height) > tolerance {
                keysToRemove.append(key)
            }
        }

        if !keysToRemove.isEmpty {
            for key in keysToRemove {
                tiledWindows.removeValue(forKey: key)
            }
            rebuildHandles()
        }
    }

    // MARK: - AX Helper

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

    deinit {
        stop()
    }
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 3: Commit**

```bash
git add Sources/Swipey/EdgeHandleController.swift
git commit -m "feat: add EdgeHandleController with panel lifecycle and pruning"
```

---

### Task 5: Wire Into WindowManager and AppDelegate

Connect the tiling flow to the edge handle system.

**Files:**
- Modify: `Sources/Swipey/WindowManager.swift`
- Modify: `Sources/Swipey/AppDelegate.swift`

**Step 1: Add tile callbacks to WindowManager**

In `Sources/Swipey/WindowManager.swift`, after the `savedFrames` property (line 6), add:

```swift
var onWindowTiledToPosition: ((AXUIElement, TilePosition, NSScreen) -> Void)?
var onWindowRestored: ((AXUIElement) -> Void)?
```

In the `tile()` method, right before the `animateTile(window:to:size:)` call, add:

```swift
onWindowTiledToPosition?(window, position, screen)
```

In the `restoreFrame()` method, right before `guard let savedFrame = savedFrames[key]`, add:

```swift
onWindowRestored?(window)
```

**Step 2: Add EdgeHandleController to AppDelegate**

In `Sources/Swipey/AppDelegate.swift`:

Add property after `zoomManager`:

```swift
private var edgeHandleController: EdgeHandleController!
```

In `applicationDidFinishLaunching`, after the `gestureMonitor.start()` line, add:

```swift
edgeHandleController = EdgeHandleController()
edgeHandleController.start()

windowManager.onWindowTiledToPosition = { [weak self] window, position, screen in
    MainActor.assumeIsolated {
        self?.edgeHandleController.registerTile(window: window, position: position, screen: screen)
    }
}
windowManager.onWindowRestored = { [weak self] window in
    MainActor.assumeIsolated {
        self?.edgeHandleController.unregisterTile(window: window)
    }
}
```

**Step 3: Build to verify**

Run: `swift build 2>&1`
Expected: Compiles successfully.

**Step 4: Run tests**

Run: `swift test 2>&1`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add Sources/Swipey/WindowManager.swift Sources/Swipey/AppDelegate.swift
git commit -m "feat: wire EdgeHandleController into tile/restore flow"
```

---

### Task 6: Manual Integration Test

No automated test — requires live accessibility + multiple windows.

**Step 1: Build and run**

Run: `swift build && .build/debug/Swipey &`

**Step 2: Test two halves**

1. Open two windows (e.g. two Finder windows)
2. Swipe one left-half, the other right-half
3. Hover mouse over the shared edge between them → resize cursor appears, thin line shows
4. Click and drag → both windows resize together
5. Release → windows stay at new size

**Step 3: Test four quarters**

1. Tile four windows into quarters
2. Hover the center vertical line → one continuous handle
3. Drag left/right → all four windows resize (both left get wider, both right get narrower)
4. Hover the center horizontal line → one continuous handle
5. Drag up/down → all four windows resize

**Step 4: Test edge cases**

- Close a tiled window → handle for that edge disappears within 2 seconds
- Manually drag a tiled window away → handle disappears (pruning)
- Restore a tiled window (swipe up) → handle disappears
- Tile only one window → no handle appears (need at least 2)
- Drag to minimum window size → stops at 200pt, doesn't go smaller

**Step 5: Kill**

Run: `killall Swipey`

**Step 6: Commit any fixes, then final**

```bash
git add -A
git commit -m "feat: grid resize v2 — hover handles on shared edges"
```
