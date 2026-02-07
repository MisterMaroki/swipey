import ApplicationServices
import Foundation
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "accessibility")

final class AccessibilityManager {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        }
        logger.warning("[Swipey] Accessibility trusted: \(self.isTrusted)")
    }

    func promptIfNeeded() {
        guard !isTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func recheckTrust() {
        let was = isTrusted
        isTrusted = AXIsProcessTrusted()
        if isTrusted != was {
            logger.warning("[Swipey] Accessibility changed: \(self.isTrusted ? "granted" : "not granted")")
        }
    }
}
