import Foundation

final class GestureStateMachine {
    enum State {
        case idle
        case tracking
        case resolved(TilePosition)
    }

    private(set) var state: State = .idle
    private var cumulativeDeltaX: Double = 0
    private var cumulativeDeltaY: Double = 0

    /// Cumulative delta threshold before the gesture activates.
    private let deadZone: Double = 30

    func begin() {
        state = .tracking
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
    }

    func feed(deltaX: Double, deltaY: Double) {
        guard case .tracking = state else { return }

        cumulativeDeltaX += deltaX
        cumulativeDeltaY += deltaY

        let absX = abs(cumulativeDeltaX)
        let absY = abs(cumulativeDeltaY)
        let magnitude = max(absX, absY)

        guard magnitude > deadZone else { return }

        if absY > absX {
            // Vertical dominant — only care about swipe up
            if cumulativeDeltaY < 0 {
                state = .resolved(.maximize)
            }
        } else {
            // Horizontal dominant
            if cumulativeDeltaX < 0 {
                state = .resolved(.leftHalf)
            } else {
                state = .resolved(.rightHalf)
            }
        }
    }

    func reset() {
        state = .idle
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
    }

    var resolvedPosition: TilePosition? {
        if case .resolved(let pos) = state { return pos }
        return nil
    }
}
