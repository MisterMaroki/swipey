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
        // Maximize, fullscreen, and restore are already at their target size — no-op.
        switch position {
        case .maximize, .fullscreen, .restore:
            return tileFrame
        default:
            break
        }

        let newWidth = min(tileFrame.width * growthFactor, visibleFrame.width)
        let newHeight = min(tileFrame.height * growthFactor, visibleFrame.height)

        let origin: CGPoint = anchoredOrigin(
            tileFrame: tileFrame,
            newSize: CGSize(width: newWidth, height: newHeight),
            position: position
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
        position: TilePosition
    ) -> CGPoint {
        let dw = newSize.width - tileFrame.width
        let dh = newSize.height - tileFrame.height

        switch position {
        // Corners: anchor to the corner
        case .topLeftQuarter:
            // Anchor top-left (NS: minX stays, maxY stays -> origin.y decreases by dh)
            return CGPoint(x: tileFrame.minX, y: tileFrame.minY - dh)
        case .topRightQuarter:
            // Anchor top-right (NS: maxX stays -> origin.x decreases by dw, maxY stays)
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
