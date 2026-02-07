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
    /// Extended vertical threshold for fullscreen (2x dead zone).
    private let fullscreenThreshold: Double = 60
    /// Secondary axis threshold for compound gestures (quarter tiling).
    private let compoundThreshold: Double = 25

    func begin() {
        state = .tracking
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
    }

    func feed(deltaX: Double, deltaY: Double) {
        switch state {
        case .idle:
            return
        case .tracking:
            feedTracking(deltaX: deltaX, deltaY: deltaY)
        case .resolved:
            feedResolved(deltaX: deltaX, deltaY: deltaY)
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

    private func feedTracking(deltaX: Double, deltaY: Double) {
        cumulativeDeltaX += deltaX
        cumulativeDeltaY += deltaY

        let absX = abs(cumulativeDeltaX)
        let absY = abs(cumulativeDeltaY)
        let magnitude = max(absX, absY)

        guard magnitude > deadZone else { return }

        if absY > absX {
            // Vertical dominant
            if cumulativeDeltaY < 0 {
                // Swipe up — check if past fullscreen threshold
                if absY > fullscreenThreshold {
                    state = .resolved(.fullscreen)
                } else {
                    state = .resolved(.maximize)
                }
            } else {
                // Swipe down — restore
                state = .resolved(.restore)
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

    private func feedResolved(deltaX: Double, deltaY: Double) {
        cumulativeDeltaX += deltaX
        cumulativeDeltaY += deltaY

        let absX = abs(cumulativeDeltaX)
        let absY = abs(cumulativeDeltaY)

        guard let currentPosition = resolvedPosition else { return }

        switch currentPosition {
        case .maximize:
            // If vertical continues upward past fullscreen threshold, upgrade
            if cumulativeDeltaY < 0 && absY > fullscreenThreshold {
                state = .resolved(.fullscreen)
            }

        case .fullscreen:
            // If vertical comes back under fullscreen threshold, downgrade to maximize
            if cumulativeDeltaY < 0 && absY <= fullscreenThreshold && absY > deadZone {
                state = .resolved(.maximize)
            }

        case .leftHalf:
            // Check for compound vertical movement -> quarter
            if absY > compoundThreshold {
                if cumulativeDeltaY < 0 {
                    state = .resolved(.topLeftQuarter)
                } else {
                    state = .resolved(.bottomLeftQuarter)
                }
            }

        case .rightHalf:
            if absY > compoundThreshold {
                if cumulativeDeltaY < 0 {
                    state = .resolved(.topRightQuarter)
                } else {
                    state = .resolved(.bottomRightQuarter)
                }
            }

        case .topLeftQuarter:
            // Allow switching between top/bottom quarters as vertical delta changes
            if absX > absY || absY <= compoundThreshold {
                state = .resolved(.leftHalf)
            } else if cumulativeDeltaY > 0 {
                state = .resolved(.bottomLeftQuarter)
            }

        case .bottomLeftQuarter:
            if absX > absY || absY <= compoundThreshold {
                state = .resolved(.leftHalf)
            } else if cumulativeDeltaY < 0 {
                state = .resolved(.topLeftQuarter)
            }

        case .topRightQuarter:
            if absX > absY || absY <= compoundThreshold {
                state = .resolved(.rightHalf)
            } else if cumulativeDeltaY > 0 {
                state = .resolved(.bottomRightQuarter)
            }

        case .bottomRightQuarter:
            if absX > absY || absY <= compoundThreshold {
                state = .resolved(.rightHalf)
            } else if cumulativeDeltaY < 0 {
                state = .resolved(.topRightQuarter)
            }

        case .restore:
            break
        }
    }
}
