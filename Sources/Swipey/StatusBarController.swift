import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let accessibilityMenuItem: NSMenuItem
    private let accessibilityManager: AccessibilityManager
    private let updateController: UpdateController
    private var launchAtLoginItem: NSMenuItem!
    var onShowTutorial: (() -> Void)?
    var onShowSettings: (() -> Void)?

    init(accessibilityManager: AccessibilityManager, updateController: UpdateController) {
        self.updateController = updateController
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

        // Settings
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Tutorial
        let tutorialItem = NSMenuItem(title: "Show Tutorial", action: #selector(showTutorial), keyEquivalent: "")
        tutorialItem.target = self
        menu.addItem(tutorialItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates\u{2026}", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        // Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

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

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func showTutorial() {
        onShowTutorial?()
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
