import AppKit
@preconcurrency import Sparkle

@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        guard ensureWriteAccess() else { return }
        controller.checkForUpdates(nil)
    }

    /// Check if the app bundle is writable. If not, prompt the user to fix ownership.
    private func ensureWriteAccess() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return true }
        if FileManager.default.isWritableFile(atPath: bundlePath) { return true }

        let alert = NSAlert()
        alert.messageText = "Update Permission Required"
        alert.informativeText = "Swipey needs write access to its application folder to install updates.\n\nClick \"Grant Access\" to fix this (you'll be asked for your password), or move Swipey to a location you own."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        // Fix ownership so future updates don't need auth
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"chown -R $(whoami) '\(bundlePath)'\" with administrator privileges"
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
