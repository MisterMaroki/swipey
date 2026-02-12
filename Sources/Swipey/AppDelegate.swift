import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var accessibilityManager: AccessibilityManager!
    private var statusBarController: StatusBarController!
    private var windowManager: WindowManager!
    private var gestureMonitor: GestureMonitor!
    private var previewOverlay: PreviewOverlay!
    private var cursorIndicator: CursorIndicator!
    private var permissionTimer: Timer?
    private var onboardingController: OnboardingController?
    private var onboardingTriggered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        accessibilityManager = AccessibilityManager()
        statusBarController = StatusBarController(accessibilityManager: accessibilityManager)
        windowManager = WindowManager()
        previewOverlay = PreviewOverlay()
        cursorIndicator = CursorIndicator()
        gestureMonitor = GestureMonitor(windowManager: windowManager, previewOverlay: previewOverlay, cursorIndicator: cursorIndicator)
        gestureMonitor.start()

        gestureMonitor.onTileAction = { [weak self] position in
            MainActor.assumeIsolated {
                self?.onboardingController?.handleTileAction(position)
            }
        }

        gestureMonitor.onGestureCancelled = { [weak self] in
            MainActor.assumeIsolated {
                self?.onboardingController?.handleGestureCancelled()
            }
        }

        statusBarController.onShowTutorial = { [weak self] in
            self?.startOnboarding()
        }

        // Periodically re-check accessibility and retry event tap if needed
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.accessibilityManager.recheckTrust()
                self.statusBarController.updateAccessibilityLabel()

                // If permission was just granted but event tap isn't running, retry
                if self.accessibilityManager.isTrusted && !self.gestureMonitor.isRunning {
                    logger.warning("[Swipey] Accessibility granted — retrying event tap...")
                    self.gestureMonitor.start()
                }

                // First-launch onboarding: show once accessibility is granted
                if self.accessibilityManager.isTrusted && !self.onboardingTriggered {
                    self.onboardingTriggered = true
                    if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                        self.startOnboarding()
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
    }

    private func startOnboarding() {
        let controller = OnboardingController()
        self.onboardingController = controller
        controller.onComplete = { [weak self] in
            self?.onboardingController = nil
        }
        controller.start()
    }
}
