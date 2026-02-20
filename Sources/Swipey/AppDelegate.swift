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
    private var edgeResizeManager: EdgeResizeManager!
    private var keyboardTileMonitor: KeyboardTileMonitor!
    private var settingsWindow: SettingsWindow?
    private var updateController: UpdateController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        updateController = UpdateController()

        accessibilityManager = AccessibilityManager()
        statusBarController = StatusBarController(accessibilityManager: accessibilityManager, updateController: updateController)
        windowManager = WindowManager()
        previewOverlay = PreviewOverlay()
        cursorIndicator = CursorIndicator()
        gestureMonitor = GestureMonitor(windowManager: windowManager, previewOverlay: previewOverlay, cursorIndicator: cursorIndicator)
        gestureMonitor.start()

        zoomManager = ZoomManager(windowManager: windowManager)
        zoomToggleMonitor = ZoomToggleMonitor()
        zoomToggleMonitor.reconfigure(triggerKey: .current)
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

        edgeResizeManager = EdgeResizeManager()

        keyboardTileMonitor = KeyboardTileMonitor(windowManager: windowManager)
        keyboardTileMonitor.onWindowTiled = { [weak self] window in
            self?.zoomManager.clearZoomState(for: window)
        }
        keyboardTileMonitor.onTileAction = { [weak self] position in
            MainActor.assumeIsolated {
                self?.onboardingController?.handleTileAction(position)
                self?.edgeResizeManager.scheduleRebuild()
            }
        }
        keyboardTileMonitor.start()

        gestureMonitor.onTileAction = { [weak self] position in
            MainActor.assumeIsolated {
                self?.onboardingController?.handleTileAction(position)
                self?.edgeResizeManager.scheduleRebuild()
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

        statusBarController.onShowSettings = { [weak self] in
            self?.showSettings()
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

                if self.accessibilityManager.isTrusted && !self.keyboardTileMonitor.isRunning {
                    self.keyboardTileMonitor.start()
                }

                // First-launch onboarding: show once accessibility is granted
                if self.accessibilityManager.isTrusted && !self.onboardingTriggered {
                    self.onboardingTriggered = true
                    let completedVersion = UserDefaults.standard.integer(forKey: "onboardingCompletedVersion")
                    if completedVersion < kOnboardingVersion {
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
        controller.onTriggerKeyChanged = { [weak self] key in
            self?.zoomToggleMonitor.reconfigure(triggerKey: key)
        }
        controller.start(triggerKey: .current)
    }

    private func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = SettingsWindow()
        win.onTriggerKeyChanged = { [weak self] key in
            self?.zoomToggleMonitor.reconfigure(triggerKey: key)
        }
        self.settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
