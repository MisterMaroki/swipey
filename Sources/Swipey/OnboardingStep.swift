struct OnboardingStep {
    let instruction: String
    let expectedPositions: Set<TilePosition>
    let acceptsCancellation: Bool
    let completionMessage: String

    init(instruction: String, expectedPositions: Set<TilePosition>, acceptsCancellation: Bool = false, completionMessage: String) {
        self.instruction = instruction
        self.expectedPositions = expectedPositions
        self.acceptsCancellation = acceptsCancellation
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
            expectedPositions: [],
            acceptsCancellation: true,
            completionMessage: "Cancelled! Now you know how to bail out."
        ),
    ]
}
