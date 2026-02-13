import AppKit
import QuartzCore

/// Animated illustration showing a mini window with a highlighted title bar
/// and a sweeping two-finger arrow in the specified direction.
@MainActor
final class TitleBarHintView: NSView {

    enum SwipeDirection {
        case right, downLeft, up, upFast, down, cancel
    }

    private let arrowLayer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let cancelXLayer = CALayer()
    private var currentDirection: SwipeDirection = .right

    // Mini window geometry (shared between draw and animation)
    private let windowRect = CGRect(x: 20, y: 10, width: 180, height: 110)
    private let titleBarHeight: CGFloat = 28
    private let cornerRadius: CGFloat = 10
    private let arrowSize: CGFloat = 28

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

    // MARK: - Public

    func configure(direction: SwipeDirection) {
        currentDirection = direction
        updateArrowImage()
        cancelXLayer.isHidden = (direction != .cancel)
    }

    func startAnimating() {
        layoutArrowAndGlow()
        arrowLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()
        cancelXLayer.removeAllAnimations()

        let titleBarCenterY = windowRect.maxY - titleBarHeight / 2
        let centerX = windowRect.midX

        switch currentDirection {
        case .right:
            animateSweep(xFrom: 30, xTo: 185, yFrom: titleBarCenterY, yTo: titleBarCenterY, duration: 1.6)

        case .downLeft:
            animateSweep(xFrom: 170, xTo: 30, yFrom: titleBarCenterY, yTo: windowRect.minY + 20, duration: 1.6)

        case .up:
            animateSweep(xFrom: centerX, xTo: centerX, yFrom: titleBarCenterY - 10, yTo: windowRect.maxY + 10, duration: 1.4)

        case .upFast:
            animateSweep(xFrom: centerX, xTo: centerX, yFrom: titleBarCenterY - 10, yTo: windowRect.maxY + 10, duration: 0.8)

        case .down:
            animateSweep(xFrom: centerX, xTo: centerX, yFrom: titleBarCenterY, yTo: windowRect.minY + 10, duration: 1.4)

        case .cancel:
            animateCancel(titleBarCenterY: titleBarCenterY)
        }

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
        cancelXLayer.removeAllAnimations()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Window shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 12,
                       color: NSColor.black.withAlphaComponent(0.25).cgColor)
        let windowPath = CGPath(roundedRect: windowRect, cornerWidth: cornerRadius,
                                cornerHeight: cornerRadius, transform: nil)
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor)
        ctx.addPath(windowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Window body
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor)
        ctx.addPath(windowPath)
        ctx.fillPath()

        // Title bar highlight
        let titleBarRect = CGRect(x: windowRect.minX, y: windowRect.maxY - titleBarHeight,
                                  width: windowRect.width, height: titleBarHeight)
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

        // Title bar border
        ctx.setStrokeColor(accentColor.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: titleBarRect.minX + 8, y: titleBarRect.minY))
        ctx.addLine(to: CGPoint(x: titleBarRect.maxX - 8, y: titleBarRect.minY))
        ctx.strokePath()

        // Traffic light dots
        let dotY = titleBarRect.midY
        let dotRadius: CGFloat = 4.5
        let dotColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 0.8),
            NSColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 0.8),
            NSColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 0.8),
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

        // Faux content lines
        ctx.setFillColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
        let lineY = windowRect.minY + 20
        for i in 0..<3 {
            let w: CGFloat = i == 2 ? 80 : 140
            ctx.fill(CGRect(x: windowRect.minX + 20, y: lineY + CGFloat(i) * 18, width: w, height: 6))
        }
    }

    // MARK: - Private

    private func setupLayers() {
        glowLayer.colors = [
            NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor,
            NSColor.controlAccentColor.withAlphaComponent(0.0).cgColor,
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        glowLayer.opacity = 0
        layer?.addSublayer(glowLayer)

        arrowLayer.opacity = 0
        layer?.addSublayer(arrowLayer)

        cancelXLayer.isHidden = true
        cancelXLayer.opacity = 0
        layer?.addSublayer(cancelXLayer)

        updateArrowImage()
        drawCancelXImage()
    }

    private func layoutArrowAndGlow() {
        glowLayer.frame = CGRect(x: windowRect.minX, y: windowRect.maxY - titleBarHeight,
                                 width: windowRect.width, height: titleBarHeight)
        glowLayer.cornerRadius = cornerRadius

        let titleBarCenterY = windowRect.maxY - titleBarHeight / 2
        arrowLayer.frame = CGRect(x: 30, y: titleBarCenterY - arrowSize / 2,
                                  width: arrowSize, height: arrowSize)

        cancelXLayer.frame = CGRect(x: windowRect.midX - 12, y: titleBarCenterY - 12,
                                    width: 24, height: 24)
    }

    private func animateSweep(xFrom: CGFloat, xTo: CGFloat, yFrom: CGFloat, yTo: CGFloat, duration: CFTimeInterval) {
        let halfArrow = arrowSize / 2

        // Position animation
        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.values = [
            NSValue(point: NSPoint(x: xFrom, y: yFrom)),
            NSValue(point: NSPoint(x: xTo, y: yTo)),
        ]
        posAnim.keyTimes = [0.0, 1.0]
        posAnim.duration = duration
        posAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        posAnim.repeatCount = .infinity
        posAnim.isRemovedOnCompletion = false

        // Set the initial position so the layer is positioned correctly
        arrowLayer.frame = CGRect(x: xFrom - halfArrow, y: yFrom - halfArrow,
                                  width: arrowSize, height: arrowSize)
        arrowLayer.add(posAnim, forKey: "sweep")

        // Fade
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.12, 0.75, 1.0]
        fade.duration = duration
        fade.repeatCount = .infinity
        arrowLayer.add(fade, forKey: "fade")
    }

    private func animateCancel(titleBarCenterY: CGFloat) {
        let halfArrow = arrowSize / 2
        let startX: CGFloat = 50
        let stopX: CGFloat = windowRect.midX

        // Arrow sweeps partway then stops
        arrowLayer.frame = CGRect(x: startX - halfArrow, y: titleBarCenterY - halfArrow,
                                  width: arrowSize, height: arrowSize)

        let sweepPos = CAKeyframeAnimation(keyPath: "position.x")
        sweepPos.values = [startX, stopX, stopX, stopX, startX]
        sweepPos.keyTimes = [0.0, 0.25, 0.5, 0.85, 1.0]
        sweepPos.duration = 3.0
        sweepPos.repeatCount = .infinity
        arrowLayer.add(sweepPos, forKey: "sweep")

        let arrowFade = CAKeyframeAnimation(keyPath: "opacity")
        arrowFade.values = [0.0, 1.0, 0.6, 0.3, 0.0]
        arrowFade.keyTimes = [0.0, 0.15, 0.3, 0.8, 1.0]
        arrowFade.duration = 3.0
        arrowFade.repeatCount = .infinity
        arrowLayer.add(arrowFade, forKey: "fade")

        // Cancel X fades in after arrow stops, then fades out
        cancelXLayer.frame = CGRect(x: stopX - 12, y: titleBarCenterY - 12, width: 24, height: 24)
        let xFade = CAKeyframeAnimation(keyPath: "opacity")
        xFade.values = [0.0, 0.0, 1.0, 1.0, 0.0]
        xFade.keyTimes = [0.0, 0.3, 0.4, 0.8, 1.0]
        xFade.duration = 3.0
        xFade.repeatCount = .infinity
        cancelXLayer.add(xFade, forKey: "fade")
    }

    private func updateArrowImage() {
        let rotation: CGFloat
        switch currentDirection {
        case .right, .cancel:  rotation = 0
        case .downLeft:        rotation = .pi * 0.75   // 135° CW (points down-left)
        case .up:              rotation = -.pi / 2     // points up
        case .upFast:          rotation = -.pi / 2
        case .down:            rotation = .pi / 2      // points down
        }

        let size = arrowSize
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let accent = NSColor.controlAccentColor
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Rotate around center
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)

            let midY = rect.midY
            let fingerSpacing: CGFloat = 5
            let lineStart: CGFloat = 3
            let lineEnd: CGFloat = rect.width - 9

            // Two parallel lines (two fingers)
            ctx.move(to: CGPoint(x: lineStart, y: midY - fingerSpacing))
            ctx.addLine(to: CGPoint(x: lineEnd, y: midY - fingerSpacing))
            ctx.strokePath()

            ctx.move(to: CGPoint(x: lineStart, y: midY + fingerSpacing))
            ctx.addLine(to: CGPoint(x: lineEnd, y: midY + fingerSpacing))
            ctx.strokePath()

            // Arrowhead
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

    private func drawCancelXImage() {
        let size: CGFloat = 24
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)

            let inset: CGFloat = 5
            ctx.move(to: CGPoint(x: inset, y: inset))
            ctx.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
            ctx.strokePath()

            ctx.move(to: CGPoint(x: rect.width - inset, y: inset))
            ctx.addLine(to: CGPoint(x: inset, y: rect.height - inset))
            ctx.strokePath()

            return true
        }

        cancelXLayer.contents = image
        cancelXLayer.contentsGravity = .resizeAspect
    }
}
