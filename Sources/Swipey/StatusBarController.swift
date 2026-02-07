import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let accessibilityMenuItem: NSMenuItem
    private let accessibilityManager: AccessibilityManager

    init(accessibilityManager: AccessibilityManager) {
        self.accessibilityManager = accessibilityManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        accessibilityMenuItem = NSMenuItem()
        accessibilityMenuItem.isEnabled = false

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Swipey")
        }

        let menu = NSMenu()
        menu.addItem(accessibilityMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Swipey", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu

        updateAccessibilityLabel()
    }

    func updateAccessibilityLabel() {
        accessibilityManager.recheckTrust()
        let status = accessibilityManager.isTrusted ? "Granted" : "Not Granted"
        accessibilityMenuItem.title = "Accessibility: \(status)"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
