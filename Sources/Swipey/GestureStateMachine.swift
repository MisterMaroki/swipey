import Foundation

final class GestureStateMachine {
    enum State: Equatable {
        case idle
        case tracking
        case resolved(TilePosition)
    }

    private(set) var state: State = .idle
    private var cumulativeDeltaX: Double = 0
    private var cumulativeDeltaY: Double = 0

    /// Cumulative delta threshold before the gesture activates.
    private let deadZone: Double = 30
    /// Extended vertical threshold for fullscreen (requires a long deliberate swipe).
    private let fullscreenThreshold: Double = 150
    /// Secondary axis threshold for compound gestures (quarter tiling).
    private let compoundThreshold: Double = 25

    func begin() {
        state = .tracking
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
    }

    func feed(deltaX: Double, deltaY: Double) {
        guard state != .idle else { return }

        cumulativeDeltaX += deltaX
        cumulativeDeltaY += deltaY

        if let position = resolveFromDeltas() {
            state = .resolved(position)
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

    // MARK: - Private

    /// Resolve a tile position from current cumulative deltas, or nil if still in dead zone.
    private func resolveFromDeltas() -> TilePosition? {
        let absX = abs(cumulativeDeltaX)
        let absY = abs(cumulativeDeltaY)
        let magnitude = max(absX, absY)

        guard magnitude > deadZone else { return nil }

        if absY > absX {
            // Vertical dominant — check for compound horizontal movement (vertical halves)
            if absX > compoundThreshold {
                return cumulativeDeltaY < 0 ? .topHalf : .bottomHalf
            }
            if cumulativeDeltaY < 0 {
                return absY > fullscreenThreshold ? .fullscreen : .maximize
            } else {
                return .restore
            }
        } else {
            // Horizontal dominant — check for compound vertical movement (quarters)
            if absY > compoundThreshold {
                if cumulativeDeltaX < 0 {
                    return cumulativeDeltaY < 0 ? .topLeftQuarter : .bottomLeftQuarter
                } else {
                    return cumulativeDeltaY < 0 ? .topRightQuarter : .bottomRightQuarter
                }
            }
            return cumulativeDeltaX < 0 ? .leftHalf : .rightHalf
        }
    }
}
