import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "onboarding")

@MainActor
final class OnboardingController: NSObject {
    private var window: OnboardingWindow?
    private var currentStepIndex = 0
    private let steps = OnboardingStep.steps
    var onComplete: (() -> Void)?

    private func playSuccess() { NSSound(named: "Glass")?.play() }
    private func playNotQuite() { NSSound(named: "Funk")?.play() }

    private func playCrescendo() {
        let sounds: [NSSound.Name] = ["Morse", "Tink", "Glass"]
        for (i, name) in sounds.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                NSSound(named: name)?.play()
            }
        }
    }

    func start() {
        currentStepIndex = 0

        let win = OnboardingWindow()
        self.window = win

        win.delegate = self
        win.showStep(index: 0, total: steps.count, instruction: steps[0].instruction, hint: steps[0].hint)

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        playCrescendo()
        scheduleAutoAdvanceIfNeeded()

        logger.warning("[Swipey] Onboarding started")
    }

    private func scheduleAutoAdvanceIfNeeded() {
        guard currentStepIndex < steps.count,
              let delay = steps[currentStepIndex].autoAdvanceDelay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            guard self.currentStepIndex < self.steps.count,
                  self.steps[self.currentStepIndex].autoAdvanceDelay != nil else { return }
            self.advanceStep()
        }
    }

    func handleGestureCancelled() {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }
        guard steps[currentStepIndex].acceptsCancellation else { return }
        advanceStep()
    }

    func handleTileAction(_ position: TilePosition) {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        if step.expectedPositions.contains(position) {
            advanceStep()
        } else if !step.expectedPositions.isEmpty {
            playNotQuite()
        }
    }

    func handleZoomActivated() {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        if step.acceptsZoomActivated {
            advanceStep()
        } else if step.acceptsZoomHoldReleased {
            playNotQuite()
        }
    }

    func handleZoomHoldReleased() {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        if step.acceptsZoomHoldReleased {
            advanceStep()
        } else if step.acceptsZoomActivated {
            playNotQuite()
        }
    }

    private func advanceStep() {
        guard let window else { return }
        playSuccess()

        let message = steps[currentStepIndex].completionMessage
        window.showCompletion(message: message, index: currentStepIndex, total: steps.count)
        logger.warning("[Swipey] Onboarding step \(self.currentStepIndex + 1) completed")

        currentStepIndex += 1

        if currentStepIndex < steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                window.showStep(
                    index: self.currentStepIndex,
                    total: self.steps.count,
                    instruction: self.steps[self.currentStepIndex].instruction,
                    hint: self.steps[self.currentStepIndex].hint
                )
                self.scheduleAutoAdvanceIfNeeded()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                window.showFinal()
                UserDefaults.standard.set(kOnboardingVersion, forKey: "onboardingCompletedVersion")
                logger.warning("[Swipey] Onboarding completed")

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
