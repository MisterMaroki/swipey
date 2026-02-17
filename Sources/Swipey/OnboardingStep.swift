import Foundation

enum StepHint: Sendable {
    case none
    case welcome
    case titleBarDiagram
    case indicator(TilePosition)
    case cancelIndicator
    case doubleTapCmd, holdCmd
}

struct OnboardingStep: Sendable {
    let instruction: String
    let expectedPositions: Set<TilePosition>
    let acceptsCancellation: Bool
    let acceptsZoomActivated: Bool
    let acceptsZoomHoldReleased: Bool
    let completionMessage: String
    let hint: StepHint
    let trackpadGesture: TrackpadHintView.Gesture?
    /// If set, the step auto-advances after this delay (no user action needed).
    let autoAdvanceDelay: TimeInterval?

    init(
        instruction: String,
        expectedPositions: Set<TilePosition> = [],
        acceptsCancellation: Bool = false,
        acceptsZoomActivated: Bool = false,
        acceptsZoomHoldReleased: Bool = false,
        hint: StepHint = .none,
        trackpadGesture: TrackpadHintView.Gesture? = nil,
        autoAdvanceDelay: TimeInterval? = nil,
        completionMessage: String
    ) {
        self.instruction = instruction
        self.expectedPositions = expectedPositions
        self.acceptsCancellation = acceptsCancellation
        self.acceptsZoomActivated = acceptsZoomActivated
        self.acceptsZoomHoldReleased = acceptsZoomHoldReleased
        self.hint = hint
        self.trackpadGesture = trackpadGesture
        self.autoAdvanceDelay = autoAdvanceDelay
        self.completionMessage = completionMessage
    }

    static let steps: [OnboardingStep] = [
        OnboardingStep(
            instruction: "",
            hint: .welcome,
            autoAdvanceDelay: 3.0,
            completionMessage: "Let's go!"
        ),
        OnboardingStep(
            instruction: "Swipe right on the title bar\nor press ⌃⌥→",
            expectedPositions: [.rightHalf],
            hint: .titleBarDiagram,
            trackpadGesture: .swipeRight,
            completionMessage: "Nice! You tiled to the right half."
        ),
        OnboardingStep(
            instruction: "Start a swipe, then hold still to cancel",
            acceptsCancellation: true,
            hint: .cancelIndicator,
            trackpadGesture: .swipeAndHold,
            completionMessage: "Cancelled! Now you know how to bail out."
        ),
        OnboardingStep(
            instruction: "Swipe to the bottom-left quarter\nor press ⌃⌥← then ⌃⌥↓",
            expectedPositions: [.bottomLeftQuarter],
            hint: .indicator(.bottomLeftQuarter),
            trackpadGesture: .swipeDownLeft,
            completionMessage: "Great! You nailed the quarter tile."
        ),
        OnboardingStep(
            instruction: "Swipe up to maximise\nor press ⌃⌥↑",
            expectedPositions: [.maximize],
            hint: .indicator(.maximize),
            trackpadGesture: .swipeUp,
            completionMessage: "Maximised! Now try going faster for fullscreen."
        ),
        OnboardingStep(
            instruction: "Swipe up faster for fullscreen\nor press ⌃⌥↑ again",
            expectedPositions: [.fullscreen],
            hint: .indicator(.fullscreen),
            trackpadGesture: .swipeUpFast,
            completionMessage: "Fullscreen! Looking good."
        ),
        OnboardingStep(
            instruction: "Swipe down to restore\nor press ⌃⌥↓",
            expectedPositions: [
                .restore, .leftHalf, .rightHalf, .topHalf, .bottomHalf,
                .maximize, .topLeftQuarter, .topRightQuarter,
                .bottomLeftQuarter, .bottomRightQuarter,
            ],
            hint: .indicator(.restore),
            trackpadGesture: .swipeDown,
            completionMessage: "You're a natural!"
        ),
        OnboardingStep(
            instruction: "Tile to the bottom-right quarter\nor press ⌃⌥→ then ⌃⌥↓",
            expectedPositions: [.bottomRightQuarter],
            hint: .indicator(.bottomRightQuarter),
            trackpadGesture: .swipeDownRight,
            completionMessage: "Perfect! Now let's expand it."
        ),
        OnboardingStep(
            instruction: "Double-tap \u{2318} to expand a tiled window",
            acceptsZoomActivated: true,
            hint: .doubleTapCmd,
            completionMessage: "Zoomed! Double-tap \u{2318} again to restore."
        ),
        OnboardingStep(
            instruction: "Double-tap and hold \u{2318} to expand, then release to snap back",
            acceptsZoomHoldReleased: true,
            hint: .holdCmd,
            completionMessage: "Perfect! You've mastered zoom."
        ),
    ]
}
