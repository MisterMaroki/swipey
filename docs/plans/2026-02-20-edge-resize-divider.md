# Edge Resize Divider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Ctrl+drag grid resize with draggable divider panels on shared edges between tiled windows.

**Architecture:** Transparent NSPanels sit on each shared edge gap. They handle hover (cursor change + highlight line) and drag (resize adjacent windows via AXUIElement). An EdgeResizeManager discovers tiled windows, detects shared edges via GridSnapshot, and creates/destroys panels. Handles rebuild after every tile action.

**Tech Stack:** Swift 6, AppKit (NSPanel, NSTrackingArea, NSCursor), AXUIElement, GridSnapshot (existing)

---

### Task 1: Create EdgeHandlePanel — the NSPanel subclass

**Files:**
- Create: `Sources/Swipey/EdgeHandlePanel.swift`

**Context:** This is a borderless, non-activating NSPanel positioned over a shared edge gap between tiled windows. It handles mouse hover (cursor + highlight) and drag (resize). All coordinates are in NS screen space (bottom-left origin) since NSPanel uses NS coordinates.

The panel needs a custom content view (`EdgeHandleView`) to handle mouse events and draw the highlight line. NSPanel itself is configured but doesn't handle events — the view does.

**Step 1: Write EdgeHandlePanel.swift**

```swift
import AppKit

/// Which axis this edge handle controls.
enum EdgeHandleAxis {
    case vertical    // left/right resize cursor
    case horizontal  // up/down resize cursor
}

/// Callback info passed when a drag completes.
struct EdgeDragResult {
    let axis: EdgeHandleAxis
    /// The delta in points the edge moved (positive = right/down in CG coords).
    let delta: CGFloat
}

/// A thin transparent panel placed over a shared edge between tiled windows.
/// Handles hover (cursor change + highlight) and drag.
@MainActor
final class EdgeHandlePanel {
    let panel: NSPanel
    let axis: EdgeHandleAxis
    let sharedEdge: SharedEdge
    private let handleView: EdgeHandleView

    /// Called when drag starts — passes the shared edge being dragged.
    var onDragBegan: ((SharedEdge) -> Void)?
    /// Called continuously during drag — passes the delta from drag start in CG coordinates.
    var onDragChanged: ((CGFloat) -> Void)?
    /// Called when drag ends.
    var onDragEnded: (() -> Void)?

    init(frame: CGRect, axis: EdgeHandleAxis, sharedEdge: SharedEdge) {
        self.axis = axis
        self.sharedEdge = sharedEdge

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        self.panel = panel

        let view = EdgeHandleView(frame: NSRect(origin: .zero, size: frame.size), axis: axis)
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            self.onDragBegan?(self.sharedEdge)
        }
        view.onDragChanged = { [weak self] delta in
            self?.onDragChanged?(delta)
        }
        view.onDragEnded = { [weak self] in
            self?.onDragEnded?()
        }
        panel.contentView = view
        self.handleView = view
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}

// MARK: - EdgeHandleView

/// Custom view that draws the highlight line and handles mouse events.
private final class EdgeHandleView: NSView {
    private let axis: EdgeHandleAxis
    private var isHighlighted = false
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var trackingArea: NSTrackingArea?
    private var lastSnappedPosition: CGFloat?

    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    init(frame: NSRect, axis: EdgeHandleAxis) {
        self.axis = axis
        super.init(frame: frame)
        wantsLayer = true
        updateTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted || isDragging else { return }

        let color = NSColor.controlAccentColor.withAlphaComponent(isDragging ? 0.7 : 0.5)
        color.setFill()

        let lineRect: NSRect
        if axis == .vertical {
            // 2pt wide line centered horizontally
            let x = (bounds.width - 2) / 2
            lineRect = NSRect(x: x, y: 0, width: 2, height: bounds.height)
        } else {
            // 2pt tall line centered vertically
            let y = (bounds.height - 2) / 2
            lineRect = NSRect(x: 0, y: y, width: bounds.width, height: 2)
        }
        lineRect.fill()
    }

    // MARK: - Tracking area

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor = axis == .vertical ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Mouse events

    override func mouseEntered(with event: NSEvent) {
        guard !isDragging else { return }
        isHighlighted = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        // Store the mouse location in screen coordinates
        dragStartPoint = NSEvent.mouseLocation
        lastSnappedPosition = nil
        needsDisplay = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentPoint = NSEvent.mouseLocation
        let delta: CGFloat
        if axis == .vertical {
            delta = currentPoint.x - dragStartPoint.x
        } else {
            // NS coords: up = positive, but CG coords: down = positive
            // We negate so that dragging down in screen = positive delta in CG
            delta = -(currentPoint.y - dragStartPoint.y)
        }
        onDragChanged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isHighlighted = false
        needsDisplay = true
        onDragEnded?()
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete (or warnings only, no errors). The file compiles standalone since it only depends on AppKit and SharedEdge from GridSnapshot.swift.

**Step 3: Commit**

```bash
git add Sources/Swipey/EdgeHandlePanel.swift
git commit -m "feat: add EdgeHandlePanel for shared edge dividers"
```

---

### Task 2: Create EdgeResizeManager — lifecycle and window discovery

**Files:**
- Create: `Sources/Swipey/EdgeResizeManager.swift`

**Context:** This manager discovers tiled windows on screen, uses GridSnapshot to detect shared edges, and creates/destroys EdgeHandlePanel instances. It reuses the window discovery logic from GridResizeManager (CGWindowListCopyWindowInfo + AXUIElement matching).

Key coordinate system detail: GridSnapshot works in CG coordinates (top-left origin). EdgeHandlePanel's NSPanel frame needs NS coordinates (bottom-left origin). The conversion happens in this manager when positioning panels.

The snap logic lives here: snap targets are 1/3, 1/2, 2/3 of the screen's visible frame dimension. The 10pt detent snaps the edge coordinate to the nearest target. Haptic feedback fires once per snap via NSHapticFeedbackManager.

**Step 1: Write EdgeResizeManager.swift**

```swift
@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "edge-resize")

@MainActor
final class EdgeResizeManager {
    private var handles: [EdgeHandlePanel] = []
    private var rebuildWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    // Drag state
    private var dragSnapshot: GridSnapshot?
    private var dragWindowElements: [Int: AXUIElement] = [:]
    private var dragInitialFrames: [Int: CGRect] = [:]
    private var lastSnappedValue: CGFloat?

    /// Minimum window dimension during resize.
    private let minWindowDimension: CGFloat = 200

    /// Snap detent zone in points.
    private let snapDetent: CGFloat = 10

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRebuild()
            }
        }
    }

    deinit {
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// Schedule a debounced rebuild of edge handles (100ms).
    func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.rebuildHandles()
            }
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Handle lifecycle

    private func rebuildHandles() {
        // Remove existing handles
        for handle in handles {
            handle.close()
        }
        handles.removeAll()

        // Discover tiled windows
        let windows = discoverTiledWindows()
        guard windows.count >= 2 else { return }

        // Get screen frame in CG coordinates
        guard let mainScreen = NSScreen.screens.first else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? mainScreen

        let cgScreenOrigin = CGPoint(
            x: screen.frame.origin.x,
            y: mainScreen.frame.height - screen.frame.maxY
        )
        let screenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)

        // Build snapshot to detect shared edges
        var windowEntries: [(id: Int, frame: CGRect)] = []
        var windowElements: [Int: AXUIElement] = [:]
        for (axElement, frame) in windows {
            let key = Int(CFHash(axElement))
            windowEntries.append((id: key, frame: frame))
            windowElements[key] = axElement
        }

        let snapshot = GridSnapshot(windows: windowEntries, screenFrame: screenFrame)
        guard !snapshot.sharedEdges.isEmpty else { return }

        logger.info("[Swipey] Edge resize: found \(snapshot.sharedEdges.count) shared edge(s)")

        // Create a panel for each shared edge
        for edge in snapshot.sharedEdges {
            let panelFrame = panelFrame(for: edge, mainScreen: mainScreen)
            let axis: EdgeHandleAxis = edge.axis == .vertical ? .vertical : .horizontal

            let handle = EdgeHandlePanel(frame: panelFrame, axis: axis, sharedEdge: edge)

            handle.onDragBegan = { [weak self] sharedEdge in
                self?.handleDragBegan(sharedEdge: sharedEdge, allWindows: windowEntries, windowElements: windowElements, screenFrame: screenFrame, screen: screen)
            }
            handle.onDragChanged = { [weak self] delta in
                self?.handleDragChanged(delta: delta)
            }
            handle.onDragEnded = { [weak self] in
                self?.handleDragEnded()
            }

            handle.show()
            handles.append(handle)
        }
    }

    /// Convert a SharedEdge (CG coords) to an NSPanel frame (NS coords).
    private func panelFrame(for edge: SharedEdge, mainScreen: NSScreen) -> CGRect {
        let hitSize: CGFloat = 6

        if edge.axis == .vertical {
            // Vertical shared edge: 6pt wide, spans the shared height
            let cgX = edge.coordinate - hitSize / 2
            let cgY = edge.spanStart
            let cgHeight = edge.spanEnd - edge.spanStart

            // Convert CG (top-left) to NS (bottom-left)
            let nsX = cgX
            let nsY = mainScreen.frame.height - cgY - cgHeight
            return CGRect(x: nsX, y: nsY, width: hitSize, height: cgHeight)
        } else {
            // Horizontal shared edge: 6pt tall, spans the shared width
            let cgY = edge.coordinate - hitSize / 2
            let cgX = edge.spanStart
            let cgWidth = edge.spanEnd - edge.spanStart

            // Convert CG (top-left) to NS (bottom-left)
            let nsX = cgX
            let nsY = mainScreen.frame.height - cgY - hitSize
            return CGRect(x: nsX, y: nsY, width: cgWidth, height: hitSize)
        }
    }

    // MARK: - Drag handling

    private func handleDragBegan(
        sharedEdge: SharedEdge,
        allWindows: [(id: Int, frame: CGRect)],
        windowElements: [Int: AXUIElement],
        screenFrame: CGRect,
        screen: NSScreen
    ) {
        // Re-read current frames at drag start for accuracy
        var freshEntries: [(id: Int, frame: CGRect)] = []
        for entry in allWindows {
            if let ax = windowElements[entry.id], let frame = getFrame(of: ax) {
                freshEntries.append((id: entry.id, frame: frame))
            } else {
                freshEntries.append(entry)
            }
        }

        dragSnapshot = GridSnapshot(windows: freshEntries, screenFrame: screenFrame)
        dragWindowElements = windowElements
        dragInitialFrames = Dictionary(uniqueKeysWithValues: freshEntries.map { ($0.id, $0.frame) })
        lastSnappedValue = nil
    }

    private func handleDragChanged(delta: CGFloat) {
        guard let snapshot = dragSnapshot else { return }

        // Find the edge being dragged (first edge in the snapshot that matches our active drag)
        // We apply the delta to all windows sharing this edge
        guard let activeHandle = handles.first(where: { handle in
            // Find handle whose view is currently dragging
            handle.panel.contentView?.window?.isKeyWindow == false // panels are non-activating
        }) else { return }

        // Actually, we need to track which handle started the drag.
        // The onDragBegan closure captured the shared edge, so we use dragSnapshot directly.

        applyDrag(delta: delta, snapshot: snapshot)
    }

    private func applyDrag(delta: CGFloat, snapshot: GridSnapshot) {
        // For each shared edge in the snapshot, apply the delta to the paired windows
        for edge in snapshot.sharedEdges {
            guard let windowA = dragInitialFrames[edge.windowAId],
                  let windowB = dragInitialFrames[edge.windowBId],
                  let axA = dragWindowElements[edge.windowAId],
                  let axB = dragWindowElements[edge.windowBId] else { continue }

            var snappedDelta = delta

            // Compute snap targets based on screen dimension
            let screenDimension: CGFloat
            let edgePosition: CGFloat
            if edge.axis == .vertical {
                screenDimension = snapshot.screenFrame.width
                edgePosition = edge.coordinate + delta - snapshot.screenFrame.minX
            } else {
                screenDimension = snapshot.screenFrame.height
                edgePosition = edge.coordinate + delta - snapshot.screenFrame.minY
            }

            let snapTargets: [CGFloat] = [1.0/3, 1.0/2, 2.0/3].map { $0 * screenDimension }
            for target in snapTargets {
                if abs(edgePosition - target) < snapDetent {
                    snappedDelta = target - (edge.axis == .vertical
                        ? edge.coordinate - snapshot.screenFrame.minX
                        : edge.coordinate - snapshot.screenFrame.minY)

                    // Haptic feedback on snap transition
                    let snappedValue = target
                    if lastSnappedValue != snappedValue {
                        lastSnappedValue = snappedValue
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .alignment,
                            performanceTime: .now
                        )
                    }
                    break
                }
            }

            // If not snapping, clear last snapped value
            let isSnapping = snapTargets.contains(where: { abs((edge.axis == .vertical
                ? edge.coordinate + snappedDelta - snapshot.screenFrame.minX
                : edge.coordinate + snappedDelta - snapshot.screenFrame.minY) - $0) < 1 })
            if !isSnapping {
                lastSnappedValue = nil
            }

            if edge.axis == .vertical {
                // Window A: right edge moves by snappedDelta → width changes
                var newA = windowA
                newA.size.width = windowA.width + snappedDelta

                // Window B: left edge moves by snappedDelta → origin.x changes, width shrinks
                var newB = windowB
                newB.origin.x = windowB.origin.x + snappedDelta
                newB.size.width = windowB.width - snappedDelta

                // Clamp minimum sizes
                guard newA.width >= minWindowDimension && newB.width >= minWindowDimension else { return }

                setFrame(of: axA, to: newA)
                setFrame(of: axB, to: newB)
            } else {
                // Window A: bottom edge moves by snappedDelta → height changes
                var newA = windowA
                newA.size.height = windowA.height + snappedDelta

                // Window B: top edge moves by snappedDelta → origin.y changes, height shrinks
                var newB = windowB
                newB.origin.y = windowB.origin.y + snappedDelta
                newB.size.height = windowB.height - snappedDelta

                // Clamp minimum sizes
                guard newA.height >= minWindowDimension && newB.height >= minWindowDimension else { return }

                setFrame(of: axA, to: newA)
                setFrame(of: axB, to: newB)
            }
        }
    }

    private func handleDragEnded() {
        dragSnapshot = nil
        dragWindowElements = [:]
        dragInitialFrames = [:]
        lastSnappedValue = nil

        // Rebuild handles since window positions changed
        scheduleRebuild()
    }

    // MARK: - Window discovery

    /// Find all on-screen windows and return their AXUIElement + CG frame.
    private func discoverTiledWindows() -> [(AXUIElement, CGRect)] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var results: [(AXUIElement, CGRect)] = []

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }

            guard let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }

            let frame = CGRect(x: x, y: y, width: w, height: h)
            guard w > 100 && h > 100 else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &windowsValue
            ) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

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

    // MARK: - AX helpers

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

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete (warnings OK, no errors).

**Step 3: Commit**

```bash
git add Sources/Swipey/EdgeResizeManager.swift
git commit -m "feat: add EdgeResizeManager for shared edge divider lifecycle"
```

---

### Task 3: Fix drag tracking — track active edge per drag session

**Files:**
- Modify: `Sources/Swipey/EdgeResizeManager.swift`

**Context:** Task 2's `handleDragChanged` has a bug — it tries to find the active handle from the panel list, but that doesn't work because multiple edges may exist. The fix: store the active `SharedEdge` when drag begins (already captured in `onDragBegan`), and use it directly in `handleDragChanged`.

**Step 1: Add `activeDragEdge` property and fix the drag flow**

In `EdgeResizeManager`, add a property:
```swift
private var activeDragEdge: SharedEdge?
```

In `handleDragBegan`, set it:
```swift
activeDragEdge = sharedEdge
```

Replace `handleDragChanged` to use it:
```swift
private func handleDragChanged(delta: CGFloat) {
    guard let snapshot = dragSnapshot,
          let activeEdge = activeDragEdge else { return }
    applyDrag(delta: delta, edge: activeEdge, snapshot: snapshot)
}
```

Refactor `applyDrag` to take a single edge instead of iterating all edges:
```swift
private func applyDrag(delta: CGFloat, edge: SharedEdge, snapshot: GridSnapshot) {
    guard let windowA = dragInitialFrames[edge.windowAId],
          let windowB = dragInitialFrames[edge.windowBId],
          let axA = dragWindowElements[edge.windowAId],
          let axB = dragWindowElements[edge.windowBId] else { return }

    var snappedDelta = delta

    // Snap logic
    let screenDimension: CGFloat
    let edgePosition: CGFloat
    if edge.axis == .vertical {
        screenDimension = snapshot.screenFrame.width
        edgePosition = edge.coordinate + delta - snapshot.screenFrame.minX
    } else {
        screenDimension = snapshot.screenFrame.height
        edgePosition = edge.coordinate + delta - snapshot.screenFrame.minY
    }

    let snapTargets: [CGFloat] = [1.0/3, 1.0/2, 2.0/3].map { $0 * screenDimension }
    for target in snapTargets {
        if abs(edgePosition - target) < snapDetent {
            snappedDelta = (target + snapshot.screenFrame.minX) - edge.coordinate
            if edge.axis == .horizontal {
                snappedDelta = (target + snapshot.screenFrame.minY) - edge.coordinate
            }

            if lastSnappedValue != target {
                lastSnappedValue = target
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            break
        }
    }

    if !snapTargets.contains(where: { abs(edgePosition - $0) < snapDetent }) {
        lastSnappedValue = nil
    }

    // Apply to windows + propagate to neighbors
    if edge.axis == .vertical {
        var newA = windowA
        newA.size.width = windowA.width + snappedDelta
        var newB = windowB
        newB.origin.x = windowB.origin.x + snappedDelta
        newB.size.width = windowB.width - snappedDelta
        guard newA.width >= minWindowDimension && newB.width >= minWindowDimension else { return }
        setFrame(of: axA, to: newA)
        setFrame(of: axB, to: newB)

        // Propagate: find other edges sharing window A or B and adjust their neighbors too
        propagateToNeighbors(edge: edge, snappedDelta: snappedDelta, snapshot: snapshot)
    } else {
        var newA = windowA
        newA.size.height = windowA.height + snappedDelta
        var newB = windowB
        newB.origin.y = windowB.origin.y + snappedDelta
        newB.size.height = windowB.height - snappedDelta
        guard newA.height >= minWindowDimension && newB.height >= minWindowDimension else { return }
        setFrame(of: axA, to: newA)
        setFrame(of: axB, to: newB)

        propagateToNeighbors(edge: edge, snappedDelta: snappedDelta, snapshot: snapshot)
    }
}

/// When 4 quarters share edges, dragging the vertical divider should also move
/// windows on the other side of the horizontal divider that share the same vertical edge.
private func propagateToNeighbors(edge: SharedEdge, snappedDelta: CGFloat, snapshot: GridSnapshot) {
    for otherEdge in snapshot.sharedEdges {
        guard otherEdge.axis == edge.axis else { continue }
        // Skip the edge we're already handling
        guard otherEdge.windowAId != edge.windowAId || otherEdge.windowBId != edge.windowBId else { continue }

        // Check if this edge shares the same coordinate (same divider line)
        guard abs(otherEdge.coordinate - edge.coordinate) < 6 else { continue }

        guard let windowA = dragInitialFrames[otherEdge.windowAId],
              let windowB = dragInitialFrames[otherEdge.windowBId],
              let axA = dragWindowElements[otherEdge.windowAId],
              let axB = dragWindowElements[otherEdge.windowBId] else { continue }

        if edge.axis == .vertical {
            var newA = windowA
            newA.size.width = windowA.width + snappedDelta
            var newB = windowB
            newB.origin.x = windowB.origin.x + snappedDelta
            newB.size.width = windowB.width - snappedDelta
            guard newA.width >= minWindowDimension && newB.width >= minWindowDimension else { continue }
            setFrame(of: axA, to: newA)
            setFrame(of: axB, to: newB)
        } else {
            var newA = windowA
            newA.size.height = windowA.height + snappedDelta
            var newB = windowB
            newB.origin.y = windowB.origin.y + snappedDelta
            newB.size.height = windowB.height - snappedDelta
            guard newA.height >= minWindowDimension && newB.height >= minWindowDimension else { continue }
            setFrame(of: axA, to: newA)
            setFrame(of: axB, to: newB)
        }
    }
}
```

In `handleDragEnded`, clear it:
```swift
activeDragEdge = nil
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete.

**Step 3: Commit**

```bash
git add Sources/Swipey/EdgeResizeManager.swift
git commit -m "fix: track active edge per drag session with neighbor propagation"
```

---

### Task 4: Wire EdgeResizeManager into AppDelegate and remove GridResizeManager

**Files:**
- Modify: `Sources/Swipey/AppDelegate.swift:21,56-57,111-113`
- Delete: `Sources/Swipey/GridResizeManager.swift`

**Context:** Replace all references to `gridResizeManager` with `edgeResizeManager`. The edge resize manager is `@MainActor` and doesn't need `start()`/`stop()` — it rebuilds handles on demand. Wire up the tile action callbacks from GestureMonitor and KeyboardTileMonitor to trigger `scheduleRebuild()`.

**Step 1: Update AppDelegate.swift**

Replace line 21:
```swift
// OLD: private var gridResizeManager: GridResizeManager!
private var edgeResizeManager: EdgeResizeManager!
```

Replace lines 56-57:
```swift
// OLD: gridResizeManager = GridResizeManager()
//      gridResizeManager.start()
edgeResizeManager = EdgeResizeManager()
```

In the `gestureMonitor.onTileAction` callback (line 70-74), add rebuild call:
```swift
gestureMonitor.onTileAction = { [weak self] position in
    MainActor.assumeIsolated {
        self?.onboardingController?.handleTileAction(position)
        self?.edgeResizeManager.scheduleRebuild()
    }
}
```

In the `keyboardTileMonitor.onTileAction` callback (line 63-67), add rebuild call:
```swift
keyboardTileMonitor.onTileAction = { [weak self] position in
    MainActor.assumeIsolated {
        self?.onboardingController?.handleTileAction(position)
        self?.edgeResizeManager.scheduleRebuild()
    }
}
```

Remove the `gridResizeManager` re-check in the permission timer (lines 111-113):
```swift
// DELETE these 3 lines:
// if self.accessibilityManager.isTrusted && !self.gridResizeManager.isRunning {
//     self.gridResizeManager.start()
// }
```

**Step 2: Delete GridResizeManager.swift**

Run: `rm Sources/Swipey/GridResizeManager.swift`

**Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete. No references to GridResizeManager remain.

**Step 4: Run tests**

Run: `swift test 2>&1 | tail -10`
Expected: All existing tests pass (GridSnapshotTests still pass since GridSnapshot.swift is kept).

**Step 5: Commit**

```bash
git rm Sources/Swipey/GridResizeManager.swift
git add Sources/Swipey/AppDelegate.swift
git commit -m "refactor: replace GridResizeManager with EdgeResizeManager"
```

---

### Task 5: Manual testing and edge case fixes

**Files:**
- Possibly modify: `Sources/Swipey/EdgeResizeManager.swift`, `Sources/Swipey/EdgeHandlePanel.swift`

**Context:** Build and install the app locally, then test the following scenarios manually:

1. **Two halves (left/right):** Tile two windows as left/right halves. Hover over the vertical gap in the center. Verify: resize cursor appears, accent highlight shows. Drag left/right — both windows resize. Release — handles rebuild correctly.

2. **Two halves (top/bottom):** Same but top/bottom. Verify horizontal divider works.

3. **Four quarters:** Tile four windows. Verify: 4 shared edges detected. Drag the vertical divider — both windows on each side resize (all 4 affected). Drag the horizontal divider — same.

4. **Snap:** Drag slowly past the 1/2 mark. Verify haptic feedback and snap.

5. **Minimum size:** Drag to make one window very small. Verify it stops at 200pt.

6. **Window closed:** Close one tiled window. Verify handles are cleaned up (no stale panels).

7. **Re-tile:** Tile a window to a different position. Verify handles rebuild.

**Step 1: Build and install**

Run: `swift build -c release && cp -r .build/release/Swipey Swipey.app/Contents/MacOS/ && cp -r Swipey.app /Applications/`

Or use the full build script for a proper build.

**Step 2: Test each scenario above**

Fix any issues found. Common problems to watch for:
- Panel z-ordering: if panels appear behind windows, adjust the window level
- Coordinate conversion bugs: CG vs NS origin differences
- Tracking area not updating after panel frame changes
- Drag delta sign for horizontal edges (NS y-axis is inverted vs CG)

**Step 3: Commit fixes**

```bash
git add Sources/Swipey/EdgeResizeManager.swift Sources/Swipey/EdgeHandlePanel.swift
git commit -m "fix: edge resize testing fixes"
```

---

### Task 6: Build release, push to GitHub

**Files:**
- Modify: `.version` (via build script)
- Modify: `site/appcast.xml`, `site/index.html` (via build script)

**Step 1: Build release**

Run: `echo "2" | bash build-app.sh` (minor version bump for new feature)

**Step 2: Commit and push**

```bash
git add -A
git commit -m "feat: draggable shared edge dividers between tiled windows"
git push
```
