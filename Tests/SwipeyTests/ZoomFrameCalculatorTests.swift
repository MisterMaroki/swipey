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
        // Height should be clamped (already close to full height)
        #expect(expanded.height <= visibleFrame.height)
    }

    @Test("Maximize returns same frame (no-op)")
    func maximizeIsNoOp() {
        let tileFrame = TilePosition.maximize.frame(forVisibleFrame: visibleFrame)
        let expanded = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: .maximize,
            visibleFrame: visibleFrame
        )
        // Should return the same frame since it's already full (clamped)
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
