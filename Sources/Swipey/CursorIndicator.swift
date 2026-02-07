import AppKit

@MainActor
final class CursorIndicator {
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var currentPosition: TilePosition?
    private var hideGeneration: UInt = 0

    private let panelSize: CGFloat = 36

    func show(position: TilePosition, at cursorCG: CGPoint) {
        hideGeneration &+= 1

        if panel == nil { createPanel() }
        guard let panel, let imageView else { return }

        currentPosition = position
        imageView.image = Self.makeIcon(for: position)

        panel.setFrameOrigin(panelOrigin(for: cursorCG))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func update(position: TilePosition, at cursorCG: CGPoint) {
        guard let panel, let imageView else { return }

        panel.setFrameOrigin(panelOrigin(for: cursorCG))

        if position != currentPosition {
            currentPosition = position
            imageView.image = Self.makeIcon(for: position)
        }
    }

    /// Swap the icon to a cancel indicator (empty screen outline with dash).
    func showCancel() {
        guard let imageView else { return }
        currentPosition = nil
        imageView.image = Self.makeCancelIcon()
    }

    func hide() {
        guard let panel else { return }
        currentPosition = nil

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        let gen = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.hideGeneration == gen else { return }
            panel.orderOut(nil)
        }
    }

    // MARK: - Layout

    private func panelOrigin(for cursorCG: CGPoint) -> CGPoint {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = mainScreenHeight - cursorCG.y
        return CGPoint(x: cursorCG.x + 18, y: nsY - panelSize - 4)
    }

    // MARK: - Panel creation

    private func createPanel() {
        let s = panelSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: s, height: s))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        let inset: CGFloat = 6
        let iv = NSImageView(frame: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2))
        iv.imageScaling = .scaleProportionallyUpOrDown
        effect.addSubview(iv)

        panel.contentView = effect
        self.imageView = iv
        self.panel = panel
    }

    // MARK: - Icon rendering

    nonisolated private static func makeIcon(for position: TilePosition) -> NSImage {
        let size = NSSize(width: 24, height: 24)
        return NSImage(size: size, flipped: false) { _ in
            let screen = NSRect(x: 3, y: 5, width: 18, height: 14)
            let cr: CGFloat = 2.5
            let gap: CGFloat = 1.5
            let halfW = (screen.width - gap) / 2
            let halfH = (screen.height - gap) / 2

            switch position {
            case .leftHalf:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX, y: screen.minY,
                                          width: halfW, height: screen.height))
            case .rightHalf:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX + halfW + gap, y: screen.minY,
                                          width: halfW, height: screen.height))
            case .topLeftQuarter:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX, y: screen.minY + halfH + gap,
                                          width: halfW, height: halfH))
            case .topRightQuarter:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX + halfW + gap, y: screen.minY + halfH + gap,
                                          width: halfW, height: halfH))
            case .bottomLeftQuarter:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX, y: screen.minY,
                                          width: halfW, height: halfH))
            case .bottomRightQuarter:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX + halfW + gap, y: screen.minY,
                                          width: halfW, height: halfH))
            case .maximize:
                drawOutlined(screen: screen, cr: cr,
                             fill: screen.insetBy(dx: 0.5, dy: 0.5))
            case .fullscreen:
                let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
                NSColor.white.withAlphaComponent(0.9).setFill()
                outline.fill()
                drawExpandArrows(in: screen)
            case .restore:
                let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
                NSColor.white.withAlphaComponent(0.3).setStroke()
                outline.lineWidth = 1.2
                outline.stroke()
                drawDownArrow(in: screen)
            }

            return true
        }
    }

    nonisolated private static func makeCancelIcon() -> NSImage {
        let size = NSSize(width: 24, height: 24)
        return NSImage(size: size, flipped: false) { _ in
            let screen = NSRect(x: 3, y: 5, width: 18, height: 14)
            let cr: CGFloat = 2.5

            // Screen outline only
            let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
            NSColor.white.withAlphaComponent(0.3).setStroke()
            outline.lineWidth = 1.2
            outline.stroke()

            // Small horizontal dash in center
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: screen.midX - 4, y: screen.midY))
            dash.line(to: NSPoint(x: screen.midX + 4, y: screen.midY))
            NSColor.white.withAlphaComponent(0.5).setStroke()
            dash.lineWidth = 1.5
            dash.lineCapStyle = .round
            dash.stroke()

            return true
        }
    }

    nonisolated private static func drawOutlined(screen: NSRect, cr: CGFloat, fill fillRect: NSRect) {
        let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        outline.lineWidth = 1.2
        outline.stroke()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    nonisolated private static func drawExpandArrows(in rect: NSRect) {
        let len: CGFloat = 3
        let inset: CGFloat = 3.5
        NSColor.black.withAlphaComponent(0.5).setStroke()

        let arrow = NSBezierPath()
        arrow.lineWidth = 1.2
        arrow.lineCapStyle = .round

        // Top-right
        let tr = NSPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        arrow.move(to: NSPoint(x: tr.x - len, y: tr.y))
        arrow.line(to: tr)
        arrow.line(to: NSPoint(x: tr.x, y: tr.y - len))

        // Bottom-left
        let bl = NSPoint(x: rect.minX + inset, y: rect.minY + inset)
        arrow.move(to: NSPoint(x: bl.x + len, y: bl.y))
        arrow.line(to: bl)
        arrow.line(to: NSPoint(x: bl.x, y: bl.y + len))

        arrow.stroke()
    }

    nonisolated private static func drawDownArrow(in rect: NSRect) {
        let cx = rect.midX
        let cy = rect.midY

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: cx, y: cy + 3))
        arrow.line(to: NSPoint(x: cx, y: cy - 3))
        arrow.move(to: NSPoint(x: cx - 2.5, y: cy - 0.5))
        arrow.line(to: NSPoint(x: cx, y: cy - 3.5))
        arrow.line(to: NSPoint(x: cx + 2.5, y: cy - 0.5))

        NSColor.white.withAlphaComponent(0.9).setStroke()
        arrow.lineWidth = 1.5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
    }
}
