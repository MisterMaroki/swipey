struct OnboardingStep: Sendable {
    let instruction: String
    let expectedPositions: Set<TilePosition>
    let acceptsCancellation: Bool
    let acceptsZoomActivated: Bool
    let acceptsZoomHoldReleased: Bool
    let completionMessage: String

    init(
        instruction: String,
        expectedPositions: Set<TilePosition> = [],
        acceptsCancellation: Bool = false,
        acceptsZoomActivated: Bool = false,
        acceptsZoomHoldReleased: Bool = false,
        completionMessage: String
    ) {
        self.instruction = instruction
        self.expectedPositions = expectedPositions
        self.acceptsCancellation = acceptsCancellation
        self.acceptsZoomActivated = acceptsZoomActivated
        self.acceptsZoomHoldReleased = acceptsZoomHoldReleased
        self.completionMessage = completionMessage
    }

    static let steps: [OnboardingStep] = [
        OnboardingStep(
            instruction: "Two-finger swipe right on the title bar",
            expectedPositions: [.rightHalf],
            completionMessage: "Nice! You tiled to the right half."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe to the bottom-left quarter",
            expectedPositions: [.bottomLeftQuarter],
            completionMessage: "Great! You nailed the quarter tile."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up to maximise",
            expectedPositions: [.maximize],
            completionMessage: "Maximised! Now try going faster for fullscreen."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up faster this time for fullscreen",
            expectedPositions: [.fullscreen],
            completionMessage: "Fullscreen! Looking good."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe down to restore",
            expectedPositions: [
                .restore, .leftHalf, .rightHalf, .topHalf, .bottomHalf,
                .maximize, .topLeftQuarter, .topRightQuarter,
                .bottomLeftQuarter, .bottomRightQuarter,
            ],
            completionMessage: "You're a natural!"
        ),
        OnboardingStep(
            instruction: "Start a swipe, then hold still for 3 seconds to cancel",
            acceptsCancellation: true,
            completionMessage: "Cancelled! Now you know how to bail out."
        ),
        OnboardingStep(
            instruction: "Double-tap ⌘ to expand a tiled window",
            acceptsZoomActivated: true,
            completionMessage: "Zoomed! Double-tap ⌘ again to restore."
        ),
        OnboardingStep(
            instruction: "Double-tap and hold ⌘ to expand, then release to snap back",
            acceptsZoomHoldReleased: true,
            completionMessage: "Perfect! You've mastered zoom."
        ),
    ]
}
