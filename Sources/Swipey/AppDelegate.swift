import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var accessibilityManager: AccessibilityManager!
    private var statusBarController: StatusBarController!
    private var windowManager: WindowManager!
    private var gestureMonitor: GestureMonitor!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu-bar-only agent (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        accessibilityManager = AccessibilityManager()
        statusBarController = StatusBarController(accessibilityManager: accessibilityManager)
        windowManager = WindowManager()
        gestureMonitor = GestureMonitor(windowManager: windowManager)
        gestureMonitor.start()

        // Periodically re-check accessibility permission and update the status bar
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusBarController.updateAccessibilityLabel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
    }
}
