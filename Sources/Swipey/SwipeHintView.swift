import AppKit
import QuartzCore

/// Animated directional hint showing a chevron that sweeps in the swipe direction.
@MainActor
final class SwipeHintView: NSView {
    private var chevronLayer: CAShapeLayer?
    private var currentDirection: SwipeHint?

    private let chevronSize: CGFloat = 20
    private let sweepDistance: CGFloat = 50

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(direction: SwipeHint) {
        currentDirection = direction
        chevronLayer?.removeFromSuperlayer()

        let shape = makeChevron(direction: direction)
        layer?.addSublayer(shape)
        chevronLayer = shape

        let (from, to) = sweepPositions(direction: direction)
        shape.position = from

        addSweepAnimation(layer: shape, from: from, to: to)
    }

    func hide() {
        currentDirection = nil
        chevronLayer?.removeAllAnimations()
        chevronLayer?.removeFromSuperlayer()
        chevronLayer = nil
    }

    // MARK: - Chevron shape

    private func makeChevron(direction: SwipeHint) -> CAShapeLayer {
        let path = CGMutablePath()
        let arm: CGFloat = 8
        let thickness: CGFloat = 2.5

        // Draw a chevron pointing in the movement direction
        let angle = chevronAngle(for: direction)

        // Chevron arms: two lines meeting at a point
        // Base chevron points right (angle 0), then rotated
        path.move(to: CGPoint(x: -arm * cos(.pi / 4), y: arm * sin(.pi / 4)))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: -arm * cos(.pi / 4), y: -arm * sin(.pi / 4)))

        let layer = CAShapeLayer()
        layer.path = path
        layer.strokeColor = NSColor.controlAccentColor.cgColor
        layer.fillColor = nil
        layer.lineWidth = thickness
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.bounds = CGRect(x: -chevronSize / 2, y: -chevronSize / 2,
                              width: chevronSize, height: chevronSize)

        // Rotate to point in the swipe direction
        layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))

        return layer
    }

    private func chevronAngle(for direction: SwipeHint) -> CGFloat {
        switch direction {
        case .right:     return 0
        case .downRight: return .pi / 4
        case .down:      return .pi / 2
        case .downLeft:  return 3 * .pi / 4
        case .left:      return .pi
        case .upLeft:    return -.pi * 3 / 4
        case .up:        return -.pi / 2
        case .upRight:   return -.pi / 4
        }
    }

    // MARK: - Sweep animation

    private func sweepPositions(direction: SwipeHint) -> (CGPoint, CGPoint) {
        let cx = bounds.midX
        let cy = bounds.midY
        let d = sweepDistance / 2

        let (dx, dy): (CGFloat, CGFloat) = {
            switch direction {
            case .right:     return (d, 0)
            case .left:      return (-d, 0)
            case .up:        return (0, d)     // NS coords: up = positive Y
            case .down:      return (0, -d)
            case .upRight:   return (d * 0.7, d * 0.7)
            case .upLeft:    return (-d * 0.7, d * 0.7)
            case .downRight: return (d * 0.7, -d * 0.7)
            case .downLeft:  return (-d * 0.7, -d * 0.7)
            }
        }()

        return (CGPoint(x: cx - dx, y: cy - dy),
                CGPoint(x: cx + dx, y: cy + dy))
    }

    private func addSweepAnimation(layer: CAShapeLayer, from: CGPoint, to: CGPoint) {
        // Position sweep
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = from
        move.toValue = to
        move.duration = 1.2
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Opacity: fade in → hold → fade out
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.15, 0.7, 1.0]
        fade.duration = 1.2

        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = 1.8  // 1.2s animation + 0.6s pause
        group.repeatCount = .greatestFiniteMagnitude

        layer.add(group, forKey: "sweep")
        layer.position = to
        layer.opacity = 0
    }
}
