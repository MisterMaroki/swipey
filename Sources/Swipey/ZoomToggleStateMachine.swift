import CoreFoundation

/// Pure state machine that detects a left-Cmd -> right-Cmd (or right -> left)
/// sequence and distinguishes hold vs toggle behavior.
public struct ZoomToggleStateMachine: Sendable {

    public enum CmdSide: Sendable {
        case left, right

        var opposite: CmdSide {
            switch self {
            case .left: return .right
            case .right: return .left
            }
        }
    }

    public enum Input: Sendable {
        case cmdDown(CmdSide)
        case cmdUp(CmdSide)
        case nonModifierKey
    }

    public enum Output: Sendable, Equatable {
        /// Double-Cmd detected -- expand the window.
        case activated
        /// Second key released quickly -- collapse (hold mode).
        case holdReleased
    }

    private enum State: Sendable {
        case idle
        case firstKeyDown(side: CmdSide)
        case waitingForSecond(firstSide: CmdSide, releaseTime: CFAbsoluteTime)
        case activated(secondSide: CmdSide, activationTime: CFAbsoluteTime)
    }

    private var state: State = .idle

    /// Maximum time between first key release and second key press.
    private let sequenceTimeout: CFAbsoluteTime = 0.4
    /// Maximum hold duration to count as a "hold" (vs toggle).
    private let holdThreshold: CFAbsoluteTime = 0.5

    public init() {}

    /// Feed a keyboard event. Returns an action if the state machine triggers.
    @discardableResult
    public mutating func feed(_ input: Input, at timestamp: CFAbsoluteTime) -> Output? {
        switch state {
        case .idle:
            if case .cmdDown(let side) = input {
                state = .firstKeyDown(side: side)
            }
            return nil

        case .firstKeyDown(let side):
            switch input {
            case .cmdUp(let upSide) where upSide == side:
                state = .waitingForSecond(firstSide: side, releaseTime: timestamp)
            case .nonModifierKey:
                state = .idle
            default:
                state = .idle
            }
            return nil

        case .waitingForSecond(let firstSide, let releaseTime):
            switch input {
            case .cmdDown(let downSide) where downSide == firstSide.opposite:
                if timestamp - releaseTime <= sequenceTimeout {
                    state = .activated(secondSide: downSide, activationTime: timestamp)
                    return .activated
                } else {
                    // Timeout -- treat as new first key
                    state = .firstKeyDown(side: downSide)
                    return nil
                }
            case .cmdDown(let downSide) where downSide == firstSide:
                // Same side again -- restart as new first key
                state = .firstKeyDown(side: downSide)
                return nil
            case .nonModifierKey:
                state = .idle
                return nil
            default:
                return nil
            }

        case .activated(let secondSide, let activationTime):
            if case .cmdUp(let upSide) = input, upSide == secondSide {
                state = .idle
                if timestamp - activationTime <= holdThreshold {
                    return .holdReleased
                }
                return nil  // toggle mode -- no action on release
            }
            return nil
        }
    }
}
