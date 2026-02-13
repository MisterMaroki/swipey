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
