@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "edge-resize")

@MainActor
final class EdgeResizeManager {

    // MARK: - Properties

    private var handles: [EdgeHandlePanel] = []
    private var rebuildGeneration: Int = 0
    private var screenObserver: NSObjectProtocol?

    // Drag state
    private var dragSnapshot: GridSnapshot?
    private var dragWindowElements: [Int: AXUIElement] = [:]
    private var dragInitialFrames: [Int: CGRect] = [:]
    private var activeDragEdge: SharedEdge?
    private var lastSnappedValue: CGFloat?

    // Constants
    private let minWindowDimension: CGFloat = 200
    private let snapDetent: CGFloat = 10

    // MARK: - Init

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
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Rebuild (public API)

    func scheduleRebuild() {
        rebuildGeneration &+= 1
        let expectedGeneration = rebuildGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.rebuildGeneration == expectedGeneration else { return }
            self.rebuildHandles()
        }
    }

    private func rebuildHandles() {
        // Close all existing handles
        for handle in handles {
            handle.close()
        }
        handles.removeAll()

        let windows = discoverTiledWindows()
        guard windows.count >= 2 else {
            logger.debug("[Swipey] Edge resize: fewer than 2 tiled windows, skipping handles")
            return
        }

        guard let mainScreen = NSScreen.screens.first else { return }

        // Build screen frame in CG coordinates (top-left origin)
        let screen = NSScreen.main ?? mainScreen
        let cgScreenOrigin = CGPoint(
            x: screen.frame.origin.x,
            y: mainScreen.frame.height - screen.frame.maxY
        )
        let screenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)

        // Build window entries with stable IDs
        var windowEntries: [(id: Int, frame: CGRect)] = []
        var elementMap: [Int: AXUIElement] = [:]
        for (axElement, frame) in windows {
            let key = Int(CFHash(axElement))
            windowEntries.append((id: key, frame: frame))
            elementMap[key] = axElement
        }

        let snapshot = GridSnapshot(windows: windowEntries, screenFrame: screenFrame)
        guard !snapshot.sharedEdges.isEmpty else {
            logger.debug("[Swipey] Edge resize: no shared edges found")
            return
        }

        logger.info("[Swipey] Edge resize: found \(snapshot.sharedEdges.count) shared edge(s) across \(snapshot.windows.count) windows")

        // Create a handle panel for each shared edge
        for edge in snapshot.sharedEdges {
            let axis: EdgeHandleAxis = (edge.axis == .vertical) ? .vertical : .horizontal
            let frame = panelFrame(for: edge, mainScreen: mainScreen)

            let handle = EdgeHandlePanel(frame: frame, axis: axis, sharedEdge: edge)

            handle.onDragBegan = { [weak self] dragEdge in
                self?.handleDragBegan(edge: dragEdge, elementMap: elementMap, snapshot: snapshot)
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

    // MARK: - Panel Frame Conversion

    /// Convert a SharedEdge (CG coords, top-left origin) to an NSPanel frame (NS coords, bottom-left origin).
    private func panelFrame(for edge: SharedEdge, mainScreen: NSScreen) -> CGRect {
        let hitSize: CGFloat = 6

        switch edge.axis {
        case .vertical:
            // Vertical edge: 6pt wide strip centered on the edge's x coordinate
            let cgX = edge.coordinate - hitSize / 2
            let cgY = edge.spanStart
            let cgHeight = edge.spanEnd - edge.spanStart
            let nsY = mainScreen.frame.height - cgY - cgHeight
            return CGRect(x: cgX, y: nsY, width: hitSize, height: cgHeight)

        case .horizontal:
            // Horizontal edge: 6pt tall strip centered on the edge's y coordinate
            let cgX = edge.spanStart
            let cgWidth = edge.spanEnd - edge.spanStart
            let cgY = edge.coordinate - hitSize / 2
            let nsY = mainScreen.frame.height - cgY - hitSize
            return CGRect(x: cgX, y: nsY, width: cgWidth, height: hitSize)
        }
    }

    // MARK: - Drag Handling

    private func handleDragBegan(edge: SharedEdge, elementMap: [Int: AXUIElement], snapshot: GridSnapshot) {
        // Re-read current window frames via AXUIElement for accuracy
        var freshEntries: [(id: Int, frame: CGRect)] = []
        var freshElements: [Int: AXUIElement] = [:]
        var freshInitialFrames: [Int: CGRect] = [:]

        for entry in snapshot.windows {
            guard let axElement = elementMap[entry.id] else { continue }
            let frame = getFrame(of: axElement) ?? entry.frame
            freshEntries.append((id: entry.id, frame: frame))
            freshElements[entry.id] = axElement
            freshInitialFrames[entry.id] = frame
        }

        let freshSnapshot = GridSnapshot(windows: freshEntries, screenFrame: snapshot.screenFrame)
        dragSnapshot = freshSnapshot
        dragWindowElements = freshElements
        dragInitialFrames = freshInitialFrames
        activeDragEdge = edge
        lastSnappedValue = nil

        logger.debug("[Swipey] Edge resize: drag began on \(edge.axis == .vertical ? "vertical" : "horizontal") edge at \(edge.coordinate)")
    }

    private func handleDragChanged(delta: CGFloat) {
        guard let edge = activeDragEdge,
              let snapshot = dragSnapshot else { return }
        applyDrag(delta: delta, edge: edge, snapshot: snapshot)
    }

    private func applyDrag(delta: CGFloat, edge: SharedEdge, snapshot: GridSnapshot) {
        guard let frameA = dragInitialFrames[edge.windowAId],
              let frameB = dragInitialFrames[edge.windowBId],
              let axA = dragWindowElements[edge.windowAId],
              let axB = dragWindowElements[edge.windowBId] else { return }

        // Compute snap targets: 1/3, 1/2, 2/3 of screen dimension
        var snappedDelta = delta
        let screenDimension: CGFloat
        let edgePosition: CGFloat

        switch edge.axis {
        case .vertical:
            screenDimension = snapshot.screenFrame.width
            edgePosition = edge.coordinate + delta
        case .horizontal:
            screenDimension = snapshot.screenFrame.height
            edgePosition = edge.coordinate + delta
        }

        let screenOrigin: CGFloat = (edge.axis == .vertical)
            ? snapshot.screenFrame.origin.x
            : snapshot.screenFrame.origin.y

        let snapTargets: [CGFloat] = [1.0/3.0, 1.0/2.0, 2.0/3.0].map { screenOrigin + screenDimension * $0 }

        for target in snapTargets {
            if abs(edgePosition - target) <= snapDetent {
                snappedDelta = target - edge.coordinate

                // Fire haptic if snapping to a new position
                if lastSnappedValue != target {
                    lastSnappedValue = target
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                break
            }
        }

        // If not snapping to any target, clear the last snapped value
        let isSnapping = snapTargets.contains(where: { abs((edge.coordinate + snappedDelta) - $0) < 0.5 })
        if !isSnapping {
            lastSnappedValue = nil
        }

        // Compute new frames
        let newFrameA: CGRect
        let newFrameB: CGRect

        switch edge.axis {
        case .vertical:
            newFrameA = CGRect(x: frameA.origin.x, y: frameA.origin.y,
                               width: frameA.width + snappedDelta, height: frameA.height)
            newFrameB = CGRect(x: frameB.origin.x + snappedDelta, y: frameB.origin.y,
                               width: frameB.width - snappedDelta, height: frameB.height)
        case .horizontal:
            newFrameA = CGRect(x: frameA.origin.x, y: frameA.origin.y,
                               width: frameA.width, height: frameA.height + snappedDelta)
            newFrameB = CGRect(x: frameB.origin.x, y: frameB.origin.y + snappedDelta,
                               width: frameB.width, height: frameB.height - snappedDelta)
        }

        // Clamp: if either new dimension is too small, skip the update
        switch edge.axis {
        case .vertical:
            guard newFrameA.width >= minWindowDimension && newFrameB.width >= minWindowDimension else { return }
        case .horizontal:
            guard newFrameA.height >= minWindowDimension && newFrameB.height >= minWindowDimension else { return }
        }

        // Apply frames via AXUIElement
        setFrame(of: axA, to: newFrameA)
        setFrame(of: axB, to: newFrameB)

        // Propagate to neighbors for multi-window (4 quarters) support
        propagateToNeighbors(edge: edge, snappedDelta: snappedDelta, snapshot: snapshot)
    }

    private func propagateToNeighbors(edge: SharedEdge, snappedDelta: CGFloat, snapshot: GridSnapshot) {
        let tolerance: CGFloat = 6

        for otherEdge in snapshot.sharedEdges {
            // Skip the active edge itself
            guard otherEdge.windowAId != edge.windowAId || otherEdge.windowBId != edge.windowBId else { continue }

            // Must be on the same axis with the same coordinate (within tolerance)
            guard otherEdge.axis == edge.axis,
                  abs(otherEdge.coordinate - edge.coordinate) <= tolerance else { continue }

            guard let frameA = dragInitialFrames[otherEdge.windowAId],
                  let frameB = dragInitialFrames[otherEdge.windowBId],
                  let axA = dragWindowElements[otherEdge.windowAId],
                  let axB = dragWindowElements[otherEdge.windowBId] else { continue }

            let newFrameA: CGRect
            let newFrameB: CGRect

            switch otherEdge.axis {
            case .vertical:
                newFrameA = CGRect(x: frameA.origin.x, y: frameA.origin.y,
                                   width: frameA.width + snappedDelta, height: frameA.height)
                newFrameB = CGRect(x: frameB.origin.x + snappedDelta, y: frameB.origin.y,
                                   width: frameB.width - snappedDelta, height: frameB.height)
            case .horizontal:
                newFrameA = CGRect(x: frameA.origin.x, y: frameA.origin.y,
                                   width: frameA.width, height: frameA.height + snappedDelta)
                newFrameB = CGRect(x: frameB.origin.x, y: frameB.origin.y + snappedDelta,
                                   width: frameB.width, height: frameB.height - snappedDelta)
            }

            // Apply same clamp check
            switch otherEdge.axis {
            case .vertical:
                guard newFrameA.width >= minWindowDimension && newFrameB.width >= minWindowDimension else { continue }
            case .horizontal:
                guard newFrameA.height >= minWindowDimension && newFrameB.height >= minWindowDimension else { continue }
            }

            setFrame(of: axA, to: newFrameA)
            setFrame(of: axB, to: newFrameB)
        }
    }

    private func handleDragEnded() {
        logger.debug("[Swipey] Edge resize: drag ended")
        dragSnapshot = nil
        dragWindowElements = [:]
        dragInitialFrames = [:]
        activeDragEdge = nil
        lastSnappedValue = nil
        scheduleRebuild()
    }

    // MARK: - Window Discovery

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
