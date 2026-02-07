import AppKit

enum TilePosition {
    case maximize
    case leftHalf
    case rightHalf
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
        let visible = screen.visibleFrame
        let margin: CGFloat = 2
        let gap: CGFloat = 4

        switch self {
        case .maximize:
            return visible.insetBy(dx: margin, dy: margin)

        case .leftHalf:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin,
                y: visible.minY + margin,
                width: halfWidth,
                height: visible.height - margin * 2
            )

        case .rightHalf:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin + halfWidth + gap,
                y: visible.minY + margin,
                width: halfWidth,
                height: visible.height - margin * 2
            )

        case .topLeftQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin,
                y: visible.minY + margin + halfHeight + gap,
                width: halfWidth,
                height: halfHeight
            )

        case .topRightQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin + halfWidth + gap,
                y: visible.minY + margin + halfHeight + gap,
                width: halfWidth,
                height: halfHeight
            )

        case .bottomLeftQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin,
                y: visible.minY + margin,
                width: halfWidth,
                height: halfHeight
            )

        case .bottomRightQuarter:
            let halfWidth = (visible.width - margin * 2 - gap) / 2
            let halfHeight = (visible.height - margin * 2 - gap) / 2
            return CGRect(
                x: visible.minX + margin + halfWidth + gap,
                y: visible.minY + margin,
                width: halfWidth,
                height: halfHeight
            )

        case .fullscreen, .restore:
            // These are handled specially by WindowManager
            return .zero
        }
    }
}
