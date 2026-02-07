import AppKit

enum TilePosition {
    case maximize
    case leftHalf
    case rightHalf

    func frame(for screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let gap: CGFloat = 6

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
        }
    }
}
