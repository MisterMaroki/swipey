/// Pure state machine: given a window's current tile position and an arrow direction,
/// returns the new tile position (or nil for no-op).
public enum KeyboardTileStateMachine: Sendable {

    public enum ArrowDirection: Sendable {
        case left, right, up, down
    }

    /// Returns the target tile position, or nil if no transition applies.
    public static func transition(from current: TilePosition?, direction: ArrowDirection) -> TilePosition? {
        switch (current, direction) {
        // From untiled (nil)
        case (nil, .left):  return .leftHalf
        case (nil, .right): return .rightHalf
        case (nil, .up):    return .maximize
        case (nil, .down):  return nil

        // From left half
        case (.leftHalf, .up):    return .topLeftQuarter
        case (.leftHalf, .down):  return .bottomLeftQuarter
        case (.leftHalf, .right): return .rightHalf
        case (.leftHalf, .left):  return nil

        // From right half
        case (.rightHalf, .up):    return .topRightQuarter
        case (.rightHalf, .down):  return .bottomRightQuarter
        case (.rightHalf, .left):  return .leftHalf
        case (.rightHalf, .right): return nil

        // From top half
        case (.topHalf, .left):  return .topLeftQuarter
        case (.topHalf, .right): return .topRightQuarter
        case (.topHalf, .up):    return .maximize
        case (.topHalf, .down):  return .bottomHalf

        // From bottom half
        case (.bottomHalf, .left):  return .bottomLeftQuarter
        case (.bottomHalf, .right): return .bottomRightQuarter
        case (.bottomHalf, .up):    return .topHalf
        case (.bottomHalf, .down):  return .restore

        // From maximize
        case (.maximize, .up):    return .fullscreen
        case (.maximize, .down):  return .restore
        case (.maximize, .left):  return .leftHalf
        case (.maximize, .right): return .rightHalf

        // From fullscreen — only down to restore
        case (.fullscreen, .down): return .restore
        case (.fullscreen, _):     return nil

        // From top-left quarter
        case (.topLeftQuarter, .right): return .topRightQuarter
        case (.topLeftQuarter, .down):  return .bottomLeftQuarter
        case (.topLeftQuarter, .left):  return .leftHalf
        case (.topLeftQuarter, .up):    return .topHalf

        // From top-right quarter
        case (.topRightQuarter, .left):  return .topLeftQuarter
        case (.topRightQuarter, .down):  return .bottomRightQuarter
        case (.topRightQuarter, .right): return .rightHalf
        case (.topRightQuarter, .up):    return .topHalf

        // From bottom-left quarter
        case (.bottomLeftQuarter, .right): return .bottomRightQuarter
        case (.bottomLeftQuarter, .up):    return .topLeftQuarter
        case (.bottomLeftQuarter, .left):  return .leftHalf
        case (.bottomLeftQuarter, .down):  return .bottomHalf

        // From bottom-right quarter
        case (.bottomRightQuarter, .left):  return .bottomLeftQuarter
        case (.bottomRightQuarter, .up):    return .topRightQuarter
        case (.bottomRightQuarter, .right): return .rightHalf
        case (.bottomRightQuarter, .down):  return .bottomHalf

        // restore is an action, not a state — treat as untiled
        case (.restore, _): return nil

        default: return nil
        }
    }
}
