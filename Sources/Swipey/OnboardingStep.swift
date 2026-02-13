import Foundation

enum StepHint: Sendable {
    case none
    case swipeRight, swipeDownLeft, swipeUp, swipeUpFast, swipeDown, swipeCancel
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
    /// If set, the step auto-advances after this delay (no user action needed).
    let autoAdvanceDelay: TimeInterval?

    init(
        instruction: String,
        expectedPositions: Set<TilePosition> = [],
        acceptsCancellation: Bool = false,
        acceptsZoomActivated: Bool = false,
        acceptsZoomHoldReleased: Bool = false,
        hint: StepHint = .none,
        autoAdvanceDelay: TimeInterval? = nil,
        completionMessage: String
    ) {
        self.instruction = instruction
        self.expectedPositions = expectedPositions
        self.acceptsCancellation = acceptsCancellation
        self.acceptsZoomActivated = acceptsZoomActivated
        self.acceptsZoomHoldReleased = acceptsZoomHoldReleased
        self.hint = hint
        self.autoAdvanceDelay = autoAdvanceDelay
        self.completionMessage = completionMessage
    }

    static let steps: [OnboardingStep] = [
        OnboardingStep(
            instruction: "Welcome to Swipey! Let's become window tiling wizards together. Screen real estate tycoons!",
            autoAdvanceDelay: 3.0,
            completionMessage: "Let's go!"
        ),
        OnboardingStep(
            instruction: "Two-finger swipe right on the title bar",
            expectedPositions: [.rightHalf],
            hint: .swipeRight,
            completionMessage: "Nice! You tiled to the right half."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe to the bottom-left quarter",
            expectedPositions: [.bottomLeftQuarter],
            hint: .swipeDownLeft,
            completionMessage: "Great! You nailed the quarter tile."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up to maximise",
            expectedPositions: [.maximize],
            hint: .swipeUp,
            completionMessage: "Maximised! Now try going faster for fullscreen."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up faster this time for fullscreen",
            expectedPositions: [.fullscreen],
            hint: .swipeUpFast,
            completionMessage: "Fullscreen! Looking good."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe down to restore",
            expectedPositions: [
                .restore, .leftHalf, .rightHalf, .topHalf, .bottomHalf,
                .maximize, .topLeftQuarter, .topRightQuarter,
                .bottomLeftQuarter, .bottomRightQuarter,
            ],
            hint: .swipeDown,
            completionMessage: "You're a natural!"
        ),
        OnboardingStep(
            instruction: "Start a swipe, then hold still for 3 seconds to cancel",
            acceptsCancellation: true,
            hint: .swipeCancel,
            completionMessage: "Cancelled! Now you know how to bail out."
        ),
        OnboardingStep(
            instruction: "Double-tap ⌘ to expand a tiled window",
            acceptsZoomActivated: true,
            hint: .doubleTapCmd,
            completionMessage: "Zoomed! Double-tap ⌘ again to restore."
        ),
        OnboardingStep(
            instruction: "Double-tap and hold ⌘ to expand, then release to snap back",
            acceptsZoomHoldReleased: true,
            hint: .holdCmd,
            completionMessage: "Perfect! You've mastered zoom."
        ),
    ]
}
