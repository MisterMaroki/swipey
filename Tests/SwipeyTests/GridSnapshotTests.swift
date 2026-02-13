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
}
