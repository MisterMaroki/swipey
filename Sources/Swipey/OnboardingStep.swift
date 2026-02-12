struct OnboardingStep {
    let instruction: String
    let expectedPosition: TilePosition
    let completionMessage: String

    static let steps: [OnboardingStep] = [
        OnboardingStep(
            instruction: "Two-finger swipe right on the title bar",
            expectedPosition: .rightHalf,
            completionMessage: "Nice! You tiled to the right half."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe to the bottom-left quarter",
            expectedPosition: .bottomLeftQuarter,
            completionMessage: "Great! You nailed the quarter tile."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up to maximise",
            expectedPosition: .maximize,
            completionMessage: "Maximised! Now try going further."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe up a little further for fullscreen",
            expectedPosition: .fullscreen,
            completionMessage: "Fullscreen! Looking good."
        ),
        OnboardingStep(
            instruction: "Two-finger swipe down to restore",
            expectedPosition: .restore,
            completionMessage: "You're a natural!"
        ),
    ]
}
