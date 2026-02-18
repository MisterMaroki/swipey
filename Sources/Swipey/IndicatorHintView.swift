import AppKit
import QuartzCore

/// Displays a scaled-up version of the cursor indicator icon that appears
/// during gestures, so users know what to look for. Includes a gentle pulse.
@MainActor
final class IndicatorHintView: NSView {

    private let iconLayer = CALayer()
    private let captionLabel = NSTextField(labelWithString: "")
    private let iconSize: CGFloat = 72

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 120)
    }

    // MARK: - Public

    func configure(position: TilePosition) {
        iconLayer.contents = Self.renderIcon(for: position, size: iconSize)
        captionLabel.stringValue = "Look for this icon near your cursor"
    }

    func configureCancel() {
        iconLayer.contents = Self.renderCancelIcon(size: iconSize)
        captionLabel.stringValue = "Look for this icon near your cursor"
    }

    func configureKeyboard(mode: KeyboardMode, triggerKey: ZoomTriggerKey = .cmd) {
        iconLayer.contents = Self.renderKeyboardIcon(mode: mode, symbol: triggerKey.symbol, size: iconSize)
        switch mode {
        case .doubleTap:
            captionLabel.stringValue = "Double-tap either \(triggerKey.symbol) key"
        case .hold:
            captionLabel.stringValue = "Double-tap \(triggerKey.symbol), keep holding"
        }
    }

    enum KeyboardMode {
        case doubleTap, hold
    }

    func startAnimating() {
        iconLayer.removeAllAnimations()

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.08
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconLayer.add(pulse, forKey: "pulse")
    }

    func stopAnimating() {
        iconLayer.removeAllAnimations()
    }

    // MARK: - Setup

    private func setupLayers() {
        let midX = intrinsicContentSize.width / 2

        iconLayer.frame = CGRect(x: midX - iconSize / 2, y: 30,
                                 width: iconSize, height: iconSize)
        iconLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(iconLayer)

        captionLabel.font = .systemFont(ofSize: 11, weight: .regular)
        captionLabel.textColor = .tertiaryLabelColor
        captionLabel.alignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)

        NSLayoutConstraint.activate([
            captionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    override func layout() {
        super.layout()
        let midX = bounds.width / 2
        iconLayer.frame = CGRect(x: midX - iconSize / 2, y: 30,
                                 width: iconSize, height: iconSize)
    }

    // MARK: - Icon rendering (scaled-up CursorIndicator icons)

    nonisolated private static func renderIcon(for position: TilePosition, size: CGFloat) -> NSImage {
        let imgSize = NSSize(width: size, height: size)
        return NSImage(size: imgSize, flipped: false) { _ in
            let screen = NSRect(x: size * 0.1, y: size * 0.15, width: size * 0.8, height: size * 0.65)
            let cr: CGFloat = 3
            let gap: CGFloat = size * 0.03
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
            case .topHalf:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX, y: screen.minY + halfH + gap,
                                          width: screen.width, height: halfH))
            case .bottomHalf:
                drawOutlined(screen: screen, cr: cr,
                             fill: NSRect(x: screen.minX, y: screen.minY,
                                          width: screen.width, height: halfH))
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
                             fill: screen.insetBy(dx: 1, dy: 1))
            case .fullscreen:
                let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
                NSColor.white.withAlphaComponent(0.9).setFill()
                outline.fill()
                drawExpandArrows(in: screen, scale: size / 24)
            case .restore:
                let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
                NSColor.white.withAlphaComponent(0.3).setStroke()
                outline.lineWidth = 2
                outline.stroke()
                drawDownArrow(in: screen, scale: size / 24)
            }

            return true
        }
    }

    nonisolated private static func renderCancelIcon(size: CGFloat) -> NSImage {
        let imgSize = NSSize(width: size, height: size)
        return NSImage(size: imgSize, flipped: false) { _ in
            let screen = NSRect(x: size * 0.1, y: size * 0.15, width: size * 0.8, height: size * 0.65)
            let cr: CGFloat = 3

            let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
            NSColor.white.withAlphaComponent(0.3).setStroke()
            outline.lineWidth = 2
            outline.stroke()

            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: screen.midX - size * 0.12, y: screen.midY))
            dash.line(to: NSPoint(x: screen.midX + size * 0.12, y: screen.midY))
            NSColor.white.withAlphaComponent(0.5).setStroke()
            dash.lineWidth = size * 0.04
            dash.lineCapStyle = .round
            dash.stroke()

            return true
        }
    }

    nonisolated private static func renderKeyboardIcon(mode: KeyboardMode, symbol: String = "\u{2318}", size: CGFloat) -> NSImage {
        let imgSize = NSSize(width: size, height: size)
        return NSImage(size: imgSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let keyRect = rect.insetBy(dx: size * 0.12, dy: size * 0.12)
            let keyPath = CGPath(roundedRect: keyRect, cornerWidth: size * 0.15,
                                 cornerHeight: size * 0.15, transform: nil)

            // Key shadow
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4,
                           color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.addPath(keyPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Key face
            ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor)
            ctx.addPath(keyPath)
            ctx.fillPath()

            // Key border
            let accent = NSColor.controlAccentColor
            ctx.setStrokeColor(accent.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(keyPath)
            ctx.strokePath()

            // Command symbol
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let fontSize = size * 0.38
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .light),
                .foregroundColor: accent,
                .paragraphStyle: paragraphStyle,
            ]
            let str = symbol as NSString
            let strSize = str.size(withAttributes: attrs)
            let strRect = CGRect(
                x: rect.midX - strSize.width / 2,
                y: rect.midY - strSize.height / 2 + 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect, withAttributes: attrs)

            // Mode indicator - small dots below the key
            let dotY = keyRect.minY - size * 0.06
            let dotSize: CGFloat = size * 0.04
            ctx.setFillColor(accent.withAlphaComponent(0.6).cgColor)
            switch mode {
            case .doubleTap:
                // Two dots for double-tap
                ctx.fillEllipse(in: CGRect(x: rect.midX - dotSize * 2, y: dotY,
                                           width: dotSize, height: dotSize))
                ctx.fillEllipse(in: CGRect(x: rect.midX + dotSize, y: dotY,
                                           width: dotSize, height: dotSize))
            case .hold:
                // Small bar for hold
                ctx.fill(CGRect(x: rect.midX - size * 0.08, y: dotY,
                                width: size * 0.16, height: dotSize))
            }

            return true
        }
    }

    // MARK: - Drawing helpers

    nonisolated private static func drawOutlined(screen: NSRect, cr: CGFloat, fill fillRect: NSRect) {
        let outline = NSBezierPath(roundedRect: screen, xRadius: cr, yRadius: cr)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        outline.lineWidth = 2
        outline.stroke()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    nonisolated private static func drawExpandArrows(in rect: NSRect, scale: CGFloat) {
        let len: CGFloat = 3 * scale
        let inset: CGFloat = 3.5 * scale
        NSColor.black.withAlphaComponent(0.5).setStroke()

        let arrow = NSBezierPath()
        arrow.lineWidth = 1.5 * scale
        arrow.lineCapStyle = .round

        let tr = NSPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        arrow.move(to: NSPoint(x: tr.x - len, y: tr.y))
        arrow.line(to: tr)
        arrow.line(to: NSPoint(x: tr.x, y: tr.y - len))

        let bl = NSPoint(x: rect.minX + inset, y: rect.minY + inset)
        arrow.move(to: NSPoint(x: bl.x + len, y: bl.y))
        arrow.line(to: bl)
        arrow.line(to: NSPoint(x: bl.x, y: bl.y + len))

        arrow.stroke()
    }

    nonisolated private static func drawDownArrow(in rect: NSRect, scale: CGFloat) {
        let cx = rect.midX
        let cy = rect.midY

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: cx, y: cy + 3 * scale))
        arrow.line(to: NSPoint(x: cx, y: cy - 3 * scale))
        arrow.move(to: NSPoint(x: cx - 2.5 * scale, y: cy - 0.5 * scale))
        arrow.line(to: NSPoint(x: cx, y: cy - 3.5 * scale))
        arrow.line(to: NSPoint(x: cx + 2.5 * scale, y: cy - 0.5 * scale))

        NSColor.white.withAlphaComponent(0.9).setStroke()
        arrow.lineWidth = 2 * scale
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
    }
}
