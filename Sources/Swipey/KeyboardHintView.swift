import AppKit
import QuartzCore

/// Animated illustration showing a ⌘ key being double-tapped or held.
@MainActor
final class KeyboardHintView: NSView {

    enum Mode {
        case doubleTap
        case hold
    }

    private let keyLayer = CALayer()
    private let labelLayer = CATextLayer()
    private var currentMode: Mode = .doubleTap

    private let keySize: CGFloat = 64

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 100)
    }

    // MARK: - Public

    func configure(mode: Mode) {
        currentMode = mode
    }

    func startAnimating() {
        keyLayer.removeAllAnimations()
        layoutKey()

        switch currentMode {
        case .doubleTap:
            animateDoubleTap()
        case .hold:
            animateHold()
        }
    }

    func stopAnimating() {
        keyLayer.removeAllAnimations()
    }

    // MARK: - Private

    private func setupLayers() {
        drawKeyImage()
        keyLayer.opacity = 1
        layer?.addSublayer(keyLayer)
    }

    private func layoutKey() {
        let midX = bounds.width / 2
        let midY = bounds.height / 2
        keyLayer.frame = CGRect(x: midX - keySize / 2, y: midY - keySize / 2,
                                width: keySize, height: keySize)
    }

    private func animateDoubleTap() {
        // Scale down (press) twice with pauses
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 0.85, 1.0, 1.0, 0.85, 1.0, 1.0]
        scale.keyTimes = [0.0, 0.08, 0.16, 0.30, 0.38, 0.46, 1.0]
        scale.duration = 1.8
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        keyLayer.add(scale, forKey: "tap")

        // Shadow/opacity pulse on taps
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 0.7, 1.0, 1.0, 0.7, 1.0, 1.0]
        opacity.keyTimes = [0.0, 0.08, 0.16, 0.30, 0.38, 0.46, 1.0]
        opacity.duration = 1.8
        opacity.repeatCount = .infinity
        keyLayer.add(opacity, forKey: "fade")
    }

    private func animateHold() {
        // Press down (two quick taps then hold)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 0.85, 1.0, 0.85, 0.85, 0.85, 1.0, 1.0]
        scale.keyTimes = [0.0, 0.06, 0.12, 0.20, 0.50, 0.65, 0.72, 1.0]
        scale.duration = 2.5
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        keyLayer.add(scale, forKey: "tap")

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 0.7, 1.0, 0.6, 0.6, 0.6, 1.0, 1.0]
        opacity.keyTimes = [0.0, 0.06, 0.12, 0.20, 0.50, 0.65, 0.72, 1.0]
        opacity.duration = 2.5
        opacity.repeatCount = .infinity
        keyLayer.add(opacity, forKey: "fade")
    }

    private func drawKeyImage() {
        let size = keySize
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let accent = NSColor.controlAccentColor

            // Key cap shape — rounded rect with subtle gradient
            let keyRect = rect.insetBy(dx: 4, dy: 4)
            let keyPath = CGPath(roundedRect: keyRect, cornerWidth: 12, cornerHeight: 12, transform: nil)

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
            ctx.setStrokeColor(accent.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(keyPath)
            ctx.strokePath()

            // ⌘ symbol
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 28, weight: .light),
                .foregroundColor: accent,
                .paragraphStyle: paragraphStyle,
            ]
            let str = "⌘" as NSString
            let strSize = str.size(withAttributes: attrs)
            let strRect = CGRect(
                x: rect.midX - strSize.width / 2,
                y: rect.midY - strSize.height / 2 + 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect, withAttributes: attrs)

            return true
        }

        keyLayer.contents = image
        keyLayer.contentsGravity = .resizeAspect
    }
}
