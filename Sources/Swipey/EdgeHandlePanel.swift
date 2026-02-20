import AppKit

enum EdgeHandleAxis {
    case vertical    // left/right cursor — shared x-coordinate
    case horizontal  // up/down cursor — shared y-coordinate
}

@MainActor
final class EdgeHandlePanel {
    let panel: NSPanel
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

    private let pill: NSView
    private let pillLength: CGFloat = 80
    private let pillThickness: CGFloat = 5

    init(axis: EdgeHandleAxis) {
        self.axis = axis
        pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        pill.layer?.cornerRadius = pillThickness / 2
        pill.layer?.cornerCurve = .continuous
        pill.alphaValue = 0

        super.init(frame: .zero)
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        switch axis {
        case .vertical:
            let y = (bounds.height - pillLength) / 2
            let x = (bounds.width - pillThickness) / 2
            pill.frame = NSRect(x: x, y: y, width: pillThickness, height: pillLength)
        case .horizontal:
            let x = (bounds.width - pillLength) / 2
            let y = (bounds.height - pillThickness) / 2
            pill.frame = NSRect(x: x, y: y, width: pillLength, height: pillThickness)
        }
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

    private func updatePillVisibility() {
        let targetAlpha: CGFloat = (isHighlighted || isDragging) ? 1.0 : 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            pill.animator().alphaValue = targetAlpha
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        updatePillVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            isHighlighted = false
            updatePillVisibility()
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

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartPoint = NSEvent.mouseLocation
        updatePillVisibility()
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
        updatePillVisibility()
        onDragEnded?()
    }
}
