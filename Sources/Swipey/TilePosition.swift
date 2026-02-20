import AppKit

public enum TilePosition: Sendable, Hashable {
    case maximize
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case fullscreen
    case restore

    /// Whether this position needs a calculated frame (vs special handling in WindowManager).
    var needsFrame: Bool {
        switch self {
        case .fullscreen, .restore:
            return false
        default:
            return true
        }
    }

    func frame(for screen: NSScreen) -> CGRect {
        return frame(forVisibleFrame: screen.visibleFrame)
    }

    /// Calculate the tile frame for a given visible frame rectangle.
    /// Used for testing and zoom calculations without needing an NSScreen.
    public func frame(forVisibleFrame visible: CGRect) -> CGRect {
        let margin: CGFloat = 0
        let gap: CGFloat = 1

        switch self {
        case .maximize:
            return visible.insetBy(dx: margin, dy: margin)
        case .leftHalf:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                          width: halfWidth, height: visible.height - margin * 2)
        case .rightHalf:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin + halfWidth + gap, y: visible.minY + margin,
                          width: halfWidth, height: visible.height - margin * 2)
        case .topHalf:
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin, y: visible.minY + margin + halfHeight + gap,
                          width: visible.width - margin * 2, height: halfHeight)
        case .bottomHalf:
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                          width: visible.width - margin * 2, height: halfHeight)
        case .topLeftQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin, y: visible.minY + margin + halfHeight + gap,
                          width: halfWidth, height: halfHeight)
        case .topRightQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin + halfWidth + gap,
                          y: visible.minY + margin + halfHeight + gap,
                          width: halfWidth, height: halfHeight)
        case .bottomLeftQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                          width: halfWidth, height: halfHeight)
        case .bottomRightQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(x: visible.minX + margin + halfWidth + gap, y: visible.minY + margin,
                          width: halfWidth, height: halfHeight)
        case .fullscreen, .restore:
            return .zero
        }
    }
}
