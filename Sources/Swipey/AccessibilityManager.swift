import ApplicationServices

final class AccessibilityManager {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            // Use the string literal to avoid Swift 6 concurrency error on the global var
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        }
    }

    func recheckTrust() {
        isTrusted = AXIsProcessTrusted()
    }
}
