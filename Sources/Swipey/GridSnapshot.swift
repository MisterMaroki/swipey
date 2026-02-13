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

    // MARK: - Propagation

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
