import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "onboarding")

@MainActor
final class OnboardingController: NSObject {
    private var window: OnboardingWindow?
    private var currentStepIndex = 0
    private var steps: [OnboardingStep] = []
    private var triggerKey: ZoomTriggerKey = .cmd
    var onComplete: (() -> Void)?
    var onTriggerKeyChanged: ((ZoomTriggerKey) -> Void)?

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

    func start(triggerKey: ZoomTriggerKey = .current) {
        self.triggerKey = triggerKey
        self.steps = OnboardingStep.steps(for: triggerKey)
        currentStepIndex = 0

        let win = OnboardingWindow()
        self.window = win

        win.delegate = self
        win.onSiriConflictChoice = { [weak self] choice in
            self?.handleSiriConflictChoice(choice)
        }
        win.showStep(index: 0, total: steps.count, instruction: steps[0].instruction,
                     hint: steps[0].hint, trackpadGesture: steps[0].trackpadGesture)

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
        let step = steps[currentStepIndex]
        guard !step.isChoiceStep else { return }
        guard step.acceptsCancellation else { return }
        advanceStep()
    }

    func handleTileAction(_ position: TilePosition) {
        guard let window, window.isVisible else { return }
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        guard !step.isChoiceStep else { return }
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
        guard !step.isChoiceStep else { return }
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
        guard !step.isChoiceStep else { return }
        if step.acceptsZoomHoldReleased {
            advanceStep()
        } else if step.acceptsZoomActivated {
            playNotQuite()
        }
    }

    private func handleSiriConflictChoice(_ choice: SiriConflictChoice) {
        guard currentStepIndex < steps.count, steps[currentStepIndex].isChoiceStep else { return }

        switch choice {
        case .noConflict:
            advanceStep()

        case .disableSiri:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            // Stay on step so user can pick another option after adjusting settings

        case .switchToControl:
            switchTriggerKey(to: .control)

        case .switchToOption:
            switchTriggerKey(to: .option)
        }
    }

    private func switchTriggerKey(to newKey: ZoomTriggerKey) {
        ZoomTriggerKey.current = newKey
        triggerKey = newKey
        onTriggerKeyChanged?(newKey)

        // Rebuild steps with new key and advance past the choice step
        let oldIndex = currentStepIndex
        steps = OnboardingStep.steps(for: newKey)
        // The choice step no longer exists in the new steps, so oldIndex now
        // points at the hold step. Show it directly.
        currentStepIndex = min(oldIndex, steps.count - 1)
        showCurrentStep()
    }

    private func advanceStep() {
        guard let window else { return }
        let isChoice = steps[currentStepIndex].isChoiceStep

        if !isChoice {
            playSuccess()
            let message = steps[currentStepIndex].completionMessage
            window.showCompletion(message: message, index: currentStepIndex, total: steps.count)
        }
        logger.warning("[Swipey] Onboarding step \(self.currentStepIndex + 1) completed")

        currentStepIndex += 1

        if currentStepIndex < steps.count {
            let delay: TimeInterval = isChoice ? 0.0 : 1.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                self.showCurrentStep()
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

    private func showCurrentStep() {
        guard let window, currentStepIndex < steps.count else { return }
        window.showStep(
            index: currentStepIndex,
            total: steps.count,
            instruction: steps[currentStepIndex].instruction,
            hint: steps[currentStepIndex].hint,
            trackpadGesture: steps[currentStepIndex].trackpadGesture
        )
        scheduleAutoAdvanceIfNeeded()
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
