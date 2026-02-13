import AppKit
import QuartzCore

/// Animated trackpad diagram with two blue finger dots performing the gesture.
@MainActor
final class TrackpadHintView: NSView {

    enum Gesture: Sendable {
        case swipeRight
        case swipeDownLeft
        case swipeDownRight
        case swipeUp
        case swipeUpFast
        case swipeDown
        case swipeAndHold
    }

    private let finger1 = CALayer()
    private let finger2 = CALayer()
    private var currentGesture: Gesture = .swipeRight

    private let padRect = CGRect(x: 8, y: 14, width: 144, height: 94)
    private let padCornerRadius: CGFloat = 14
    private let fingerDiameter: CGFloat = 12
    private let fingerGap: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupFingers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 116)
    }

    // MARK: - Public

    func configure(gesture: Gesture) {
        currentGesture = gesture
    }

    func startAnimating() {
        finger1.removeAllAnimations()
        finger2.removeAllAnimations()
        finger1.opacity = 0
        finger2.opacity = 0

        switch currentGesture {
        case .swipeAndHold:
            animateHold()
        default:
            let (start, end, dur) = endpoints()
            animateSwipe(from: start, to: end, duration: dur)
        }
    }

    func stopAnimating() {
        finger1.removeAllAnimations()
        finger2.removeAllAnimations()
        finger1.opacity = 0
        finger2.opacity = 0
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let path = CGPath(roundedRect: padRect, cornerWidth: padCornerRadius,
                          cornerHeight: padCornerRadius, transform: nil)

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6,
                       color: NSColor.black.withAlphaComponent(0.15).cgColor)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Fill
        ctx.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // Border
        ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Label
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        ("Trackpad" as NSString).draw(
            in: CGRect(x: 0, y: 0, width: bounds.width, height: 14),
            withAttributes: attrs
        )
    }

    // MARK: - Private

    private func setupFingers() {
        let r = fingerDiameter / 2
        let accent = NSColor.controlAccentColor

        for finger in [finger1, finger2] {
            finger.bounds = CGRect(x: 0, y: 0, width: fingerDiameter, height: fingerDiameter)
            finger.cornerRadius = r
            finger.backgroundColor = accent.withAlphaComponent(0.85).cgColor
            finger.shadowColor = NSColor.black.cgColor
            finger.shadowOffset = CGSize(width: 0, height: -1)
            finger.shadowRadius = 2
            finger.shadowOpacity = 0.25
            finger.opacity = 0
            layer?.addSublayer(finger)
        }
    }

    private func endpoints() -> (start: CGPoint, end: CGPoint, duration: CFTimeInterval) {
        let midX = padRect.midX
        let midY = padRect.midY
        let m: CGFloat = 20

        switch currentGesture {
        case .swipeRight:
            return (CGPoint(x: padRect.minX + m, y: midY),
                    CGPoint(x: padRect.maxX - m, y: midY), 1.8)
        case .swipeDownLeft:
            return (CGPoint(x: padRect.maxX - m, y: padRect.maxY - m),
                    CGPoint(x: padRect.minX + m, y: padRect.minY + m), 1.8)
        case .swipeDownRight:
            return (CGPoint(x: padRect.minX + m, y: padRect.maxY - m),
                    CGPoint(x: padRect.maxX - m, y: padRect.minY + m), 1.8)
        case .swipeUp:
            return (CGPoint(x: midX, y: padRect.minY + m),
                    CGPoint(x: midX, y: padRect.maxY - m), 1.8)
        case .swipeUpFast:
            return (CGPoint(x: midX, y: padRect.minY + m),
                    CGPoint(x: midX, y: padRect.maxY - m), 1.0)
        case .swipeDown:
            return (CGPoint(x: midX, y: padRect.maxY - m),
                    CGPoint(x: midX, y: padRect.minY + m), 1.8)
        case .swipeAndHold:
            return (CGPoint(x: padRect.minX + m, y: midY),
                    CGPoint(x: midX, y: midY), 3.0)
        }
    }

    private func fingerOffsets(from start: CGPoint, to end: CGPoint) -> (CGPoint, CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        let half = fingerGap / 2

        guard len > 0 else {
            return (CGPoint(x: -half, y: 0), CGPoint(x: half, y: 0))
        }

        // Perpendicular to swipe direction
        let px = -dy / len * half
        let py = dx / len * half
        return (CGPoint(x: px, y: py), CGPoint(x: -px, y: -py))
    }

    private func animateSwipe(from start: CGPoint, to end: CGPoint, duration: CFTimeInterval) {
        let (off1, off2) = fingerOffsets(from: start, to: end)

        let f1Start = CGPoint(x: start.x + off1.x, y: start.y + off1.y)
        let f1End = CGPoint(x: end.x + off1.x, y: end.y + off1.y)
        let f2Start = CGPoint(x: start.x + off2.x, y: start.y + off2.y)
        let f2End = CGPoint(x: end.x + off2.x, y: end.y + off2.y)

        animateFinger(finger1, from: f1Start, to: f1End, duration: duration)
        animateFinger(finger2, from: f2Start, to: f2End, duration: duration)
    }

    private func animateFinger(_ finger: CALayer, from start: CGPoint, to end: CGPoint,
                               duration: CFTimeInterval) {
        finger.position = start

        let pos = CAKeyframeAnimation(keyPath: "position")
        pos.values = [
            NSValue(point: NSPoint(x: start.x, y: start.y)),
            NSValue(point: NSPoint(x: start.x, y: start.y)),
            NSValue(point: NSPoint(x: end.x, y: end.y)),
            NSValue(point: NSPoint(x: end.x, y: end.y)),
        ]
        pos.keyTimes = [0.0, 0.08, 0.65, 1.0]
        pos.duration = duration
        pos.repeatCount = .infinity
        pos.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        finger.add(pos, forKey: "move")

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0, 0.0]
        fade.keyTimes = [0.0, 0.06, 0.68, 0.82, 1.0]
        fade.duration = duration
        fade.repeatCount = .infinity
        finger.add(fade, forKey: "fade")
    }

    private func animateHold() {
        let midY = padRect.midY
        let m: CGFloat = 20
        let start = CGPoint(x: padRect.minX + m, y: midY)
        let stop = CGPoint(x: padRect.midX, y: midY)
        let duration: CFTimeInterval = 3.0

        let (off1, off2) = fingerOffsets(from: start, to: stop)

        for (finger, off) in [(finger1, off1), (finger2, off2)] {
            let fStart = CGPoint(x: start.x + off.x, y: start.y + off.y)
            let fStop = CGPoint(x: stop.x + off.x, y: stop.y + off.y)

            finger.position = fStart

            let pos = CAKeyframeAnimation(keyPath: "position")
            pos.values = [
                NSValue(point: NSPoint(x: fStart.x, y: fStart.y)),
                NSValue(point: NSPoint(x: fStart.x, y: fStart.y)),
                NSValue(point: NSPoint(x: fStop.x, y: fStop.y)),
                NSValue(point: NSPoint(x: fStop.x, y: fStop.y)),
                NSValue(point: NSPoint(x: fStop.x, y: fStop.y)),
            ]
            pos.keyTimes = [0.0, 0.05, 0.18, 0.7, 1.0]
            pos.duration = duration
            pos.repeatCount = .infinity
            pos.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            finger.add(pos, forKey: "move")

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 1.0, 1.0, 1.0, 0.0, 0.0]
            fade.keyTimes = [0.0, 0.05, 0.18, 0.7, 0.82, 1.0]
            fade.duration = duration
            fade.repeatCount = .infinity
            finger.add(fade, forKey: "fade")
        }
    }
}
