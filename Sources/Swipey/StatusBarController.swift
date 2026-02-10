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

        // Running label
        let runningItem = NSMenuItem(title: "Swipey is running", action: nil, keyEquivalent: "")
        runningItem.isEnabled = false
        menu.addItem(runningItem)

        menu.addItem(.separator())

        // Accessibility status
        menu.addItem(accessibilityMenuItem)
        let requestItem = NSMenuItem(title: "Request Access\u{2026}", action: #selector(requestAccess), keyEquivalent: "")
        requestItem.target = self
        menu.addItem(requestItem)

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(title: "About Swipey", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Swipey", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        updateAccessibilityLabel()
    }

    func updateAccessibilityLabel() {
        accessibilityManager.recheckTrust()
        let status = accessibilityManager.isTrusted ? "Granted" : "Not Granted"
        accessibilityMenuItem.title = "Accessibility: \(status)"
    }

    @objc private func requestAccess() {
        accessibilityManager.promptIfNeeded()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Swipey"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        alert.informativeText = "Version \(version)\n\nTwo-finger swipe window tiling for macOS.\nA 1273 project — 1273.co.uk\n\nMIT License"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
