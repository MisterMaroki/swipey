import AppKit

enum EdgeHandleAxis {
    case vertical    // left/right cursor — shared x-coordinate
    case horizontal  // up/down cursor — shared y-coordinate
}

@MainActor
final class EdgeHandlePanel {
    private let panel: NSPanel
    let axis: EdgeHandleAxis
    let sharedEdge: SharedEdge

    var onDragBegan: ((SharedEdge) -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    init(frame: CGRect, axis: EdgeHandleAxis, sharedEdge: SharedEdge) {
        self.axis = axis
        self.sharedEdge = sharedEdge

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hasShadow = false

        self.panel = panel

        let handleView = EdgeHandleView(axis: axis)
        handleView.onDragBegan = { [weak self] in
            guard let self else { return }
            self.onDragBegan?(self.sharedEdge)
        }
        handleView.onDragChanged = { [weak self] delta in
            self?.onDragChanged?(delta)
        }
        handleView.onDragEnded = { [weak self] in
            self?.onDragEnded?()
        }

        panel.contentView = handleView
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}

// MARK: - EdgeHandleView

private final class EdgeHandleView: NSView {
    let axis: EdgeHandleAxis

    var isHighlighted = false
    var isDragging = false
    var dragStartPoint: NSPoint = .zero

    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    init(axis: EdgeHandleAxis) {
        self.axis = axis
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            isHighlighted = false
            needsDisplay = true
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        switch axis {
        case .vertical:
            addCursorRect(bounds, cursor: .resizeLeftRight)
        case .horizontal:
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted || isDragging else { return }

        let color = NSColor.controlAccentColor.withAlphaComponent(isDragging ? 0.7 : 0.5)
        color.setFill()

        let lineRect: NSRect
        switch axis {
        case .vertical:
            let x = (bounds.width - 2) / 2
            lineRect = NSRect(x: x, y: 0, width: 2, height: bounds.height)
        case .horizontal:
            let y = (bounds.height - 2) / 2
            lineRect = NSRect(x: 0, y: y, width: bounds.width, height: 2)
        }

        lineRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartPoint = NSEvent.mouseLocation
        needsDisplay = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = NSEvent.mouseLocation
        let delta: CGFloat
        switch axis {
        case .vertical:
            delta = currentPoint.x - dragStartPoint.x
        case .horizontal:
            // Negate because NS y is bottom-up but CG y is top-down
            delta = -(currentPoint.y - dragStartPoint.y)
        }
        onDragChanged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isHighlighted = false
        needsDisplay = true
        onDragEnded?()
    }
}
