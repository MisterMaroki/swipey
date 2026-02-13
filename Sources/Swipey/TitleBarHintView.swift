import AppKit
import QuartzCore

/// Animated illustration showing a mini window with a highlighted title bar
/// and a sweeping two-finger arrow, teaching users where to swipe.
@MainActor
final class TitleBarHintView: NSView {

    private let arrowLayer = CALayer()
    private let glowLayer = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 130)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let windowRect = CGRect(x: 20, y: 10, width: 180, height: 110)
        let titleBarHeight: CGFloat = 28
        let cornerRadius: CGFloat = 10

        // Window shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        let windowPath = CGPath(roundedRect: windowRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor)
        ctx.addPath(windowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Window body
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor)
        ctx.addPath(windowPath)
        ctx.fillPath()

        // Title bar (highlighted) — top portion in NS coords (origin at bottom)
        let titleBarRect = CGRect(
            x: windowRect.minX,
            y: windowRect.maxY - titleBarHeight,
            width: windowRect.width,
            height: titleBarHeight
        )
        let titleBarPath = CGMutablePath()
        titleBarPath.move(to: CGPoint(x: titleBarRect.minX + cornerRadius, y: titleBarRect.maxY))
        titleBarPath.addArc(tangent1End: CGPoint(x: titleBarRect.maxX, y: titleBarRect.maxY),
                           tangent2End: CGPoint(x: titleBarRect.maxX, y: titleBarRect.minY),
                           radius: cornerRadius)
        titleBarPath.addLine(to: CGPoint(x: titleBarRect.maxX, y: titleBarRect.minY))
        titleBarPath.addLine(to: CGPoint(x: titleBarRect.minX, y: titleBarRect.minY))
        titleBarPath.addArc(tangent1End: CGPoint(x: titleBarRect.minX, y: titleBarRect.maxY),
                           tangent2End: CGPoint(x: titleBarRect.minX + cornerRadius, y: titleBarRect.maxY),
                           radius: cornerRadius)
        titleBarPath.closeSubpath()

        let accentColor = NSColor.controlAccentColor
        ctx.setFillColor(accentColor.withAlphaComponent(0.2).cgColor)
        ctx.addPath(titleBarPath)
        ctx.fillPath()

        // Title bar bottom border
        ctx.setStrokeColor(accentColor.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: titleBarRect.minX + 8, y: titleBarRect.minY))
        ctx.addLine(to: CGPoint(x: titleBarRect.maxX - 8, y: titleBarRect.minY))
        ctx.strokePath()

        // Traffic light dots
        let dotY = titleBarRect.midY
        let dotRadius: CGFloat = 4.5
        let dotColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 0.8),  // red
            NSColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 0.8),  // yellow
            NSColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 0.8), // green
        ]
        for (i, color) in dotColors.enumerated() {
            let dotX = titleBarRect.minX + 16 + CGFloat(i) * 16
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: dotX - dotRadius, y: dotY - dotRadius,
                                       width: dotRadius * 2, height: dotRadius * 2))
        }

        // Window outline
        ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(windowPath)
        ctx.strokePath()

        // Faux content lines in the body
        ctx.setFillColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
        let lineY = windowRect.minY + 20
        for i in 0..<3 {
            let w: CGFloat = i == 2 ? 80 : 140
            ctx.fill(CGRect(x: windowRect.minX + 20, y: lineY + CGFloat(i) * 18, width: w, height: 6))
        }
    }

    // MARK: - Animation

    func startAnimating() {
        layoutArrowAndGlow()

        // Sweep arrow right repeatedly
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = 30.0
        sweep.toValue = 185.0
        sweep.duration = 1.6
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.repeatCount = .infinity
        sweep.autoreverses = false
        arrowLayer.add(sweep, forKey: "sweep")

        // Fade in at start, fade out at end
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.12, 0.75, 1.0]
        fade.duration = 1.6
        fade.repeatCount = .infinity
        arrowLayer.add(fade, forKey: "fade")

        // Title bar glow pulse
        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = 0.0
        glow.toValue = 0.5
        glow.duration = 0.8
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glow, forKey: "glow")
    }

    func stopAnimating() {
        arrowLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()
    }

    // MARK: - Setup

    private func setupLayers() {
        // Glow layer on title bar
        glowLayer.colors = [
            NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor,
            NSColor.controlAccentColor.withAlphaComponent(0.0).cgColor,
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        glowLayer.opacity = 0
        layer?.addSublayer(glowLayer)

        // Arrow layer — two horizontal lines (representing two fingers) with arrowhead
        arrowLayer.opacity = 0
        layer?.addSublayer(arrowLayer)
        drawArrowImage()
    }

    private func layoutArrowAndGlow() {
        // Title bar glow — NS coords: title bar is at top of window
        let windowRect = CGRect(x: 20, y: 10, width: 180, height: 110)
        let titleBarHeight: CGFloat = 28
        glowLayer.frame = CGRect(
            x: windowRect.minX,
            y: windowRect.maxY - titleBarHeight,
            width: windowRect.width,
            height: titleBarHeight
        )
        glowLayer.cornerRadius = 10

        // Arrow positioned at title bar center
        let arrowSize: CGFloat = 28
        arrowLayer.frame = CGRect(
            x: 30,
            y: windowRect.maxY - titleBarHeight / 2 - arrowSize / 2,
            width: arrowSize,
            height: arrowSize
        )
    }

    private func drawArrowImage() {
        let size: CGFloat = 28
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let accent = NSColor.controlAccentColor
            ctx.setStrokeColor(accent.cgColor)
            ctx.setFillColor(accent.cgColor)
            ctx.setLineWidth(2.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Two parallel lines (two fingers)
            let midY = rect.midY
            let fingerSpacing: CGFloat = 5
            let lineStart: CGFloat = 3
            let lineEnd: CGFloat = rect.width - 9

            // Finger 1
            ctx.move(to: CGPoint(x: lineStart, y: midY - fingerSpacing))
            ctx.addLine(to: CGPoint(x: lineEnd, y: midY - fingerSpacing))
            ctx.strokePath()

            // Finger 2
            ctx.move(to: CGPoint(x: lineStart, y: midY + fingerSpacing))
            ctx.addLine(to: CGPoint(x: lineEnd, y: midY + fingerSpacing))
            ctx.strokePath()

            // Arrowhead (shared, centered)
            let tipX = rect.width - 4
            let arrowBack = tipX - 8
            let arrowSpread: CGFloat = 9
            ctx.move(to: CGPoint(x: arrowBack, y: midY - arrowSpread))
            ctx.addLine(to: CGPoint(x: tipX, y: midY))
            ctx.addLine(to: CGPoint(x: arrowBack, y: midY + arrowSpread))
            ctx.strokePath()

            return true
        }

        arrowLayer.contents = image
        arrowLayer.contentsGravity = .resizeAspect
    }
}
