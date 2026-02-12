import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "onboarding")

@MainActor
final class OnboardingController: NSObject {
    private var window: OnboardingWindow?
    private var currentStepIndex = 0
    private let steps = OnboardingStep.steps
    var onComplete: (() -> Void)?

    func start() {
        currentStepIndex = 0

        let win = OnboardingWindow()
        self.window = win

        win.delegate = self
        win.showStep(index: 0, total: steps.count, instruction: steps[0].instruction)

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        logger.warning("[Swipey] Onboarding started")
    }

    func handleTileAction(_ position: TilePosition) {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }

        let expected = steps[currentStepIndex].expectedPosition
        guard position == expected else { return }

        let message = steps[currentStepIndex].completionMessage
        window.showCompletion(message: message, index: currentStepIndex, total: steps.count)
        logger.warning("[Swipey] Onboarding step \(self.currentStepIndex + 1) completed")

        currentStepIndex += 1

        if currentStepIndex < steps.count {
            // Show next step after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                window.showStep(
                    index: self.currentStepIndex,
                    total: self.steps.count,
                    instruction: self.steps[self.currentStepIndex].instruction
                )
            }
        } else {
            // All steps done — show final screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                window.showFinal()
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                logger.warning("[Swipey] Onboarding completed")

                // Auto-close after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.close()
                }
            }
        }
    }

    private func close() {
        window?.close()
        window = nil
        onComplete?()
    }
}

extension OnboardingController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            onComplete?()
        }
    }
}
