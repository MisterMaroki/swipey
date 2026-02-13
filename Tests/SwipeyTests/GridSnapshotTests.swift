import Foundation
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
}
