import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "app")

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var accessibilityManager: AccessibilityManager!
    private var statusBarController: StatusBarController!
    private var windowManager: WindowManager!
    private var gestureMonitor: GestureMonitor!
    private var previewOverlay: PreviewOverlay!
    private var cursorIndicator: CursorIndicator!
    private var permissionTimer: Timer?
    private var onboardingController: OnboardingController?
    private var onboardingTriggered = false
    private var zoomToggleMonitor: ZoomToggleMonitor!
    private var zoomManager: ZoomManager!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        accessibilityManager = AccessibilityManager()
        statusBarController = StatusBarController(accessibilityManager: accessibilityManager)
        windowManager = WindowManager()
        previewOverlay = PreviewOverlay()
        cursorIndicator = CursorIndicator()
        gestureMonitor = GestureMonitor(windowManager: windowManager, previewOverlay: previewOverlay, cursorIndicator: cursorIndicator)
        gestureMonitor.start()

        zoomManager = ZoomManager(windowManager: windowManager)
        zoomToggleMonitor = ZoomToggleMonitor()
        zoomToggleMonitor.onActivated = { [weak self] in
            self?.zoomManager.toggleFocusedWindow()
            MainActor.assumeIsolated {
                self?.onboardingController?.handleZoomActivated()
            }
        }
        zoomToggleMonitor.onHoldReleased = { [weak self] in
            self?.zoomManager.collapseFocusedWindow()
            MainActor.assumeIsolated {
                self?.onboardingController?.handleZoomHoldReleased()
            }
        }
        zoomToggleMonitor.start()

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

        gestureMonitor.onWindowTiled = { [weak self] window in
            self?.zoomManager.clearZoomState(for: window)
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

                if self.accessibilityManager.isTrusted && !self.zoomToggleMonitor.isRunning {
                    self.zoomToggleMonitor.start()
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

    public func applicationWillTerminate(_ notification: Notification) {
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
