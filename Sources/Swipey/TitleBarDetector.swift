import ApplicationServices
import AppKit

enum TitleBarDetector {
    /// Check if the given screen-space point (CG/top-left origin) is over a window's title bar.
    /// Returns the window AXUIElement if so, nil otherwise.
    static func detectWindow(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        guard error == .success, let hitElement = element else {
            return nil
        }

        guard isTitleBarArea(hitElement) else {
            return nil
        }

        return findWindow(from: hitElement)
    }

    /// Convert NSScreen coordinates (bottom-left origin) to CG/Accessibility coordinates (top-left origin).
    static func convertToCG(_ nsPoint: CGPoint) -> CGPoint {
        guard let mainScreen = NSScreen.screens.first else { return nsPoint }
        return CGPoint(x: nsPoint.x, y: mainScreen.frame.height - nsPoint.y)
    }

    // MARK: - Private

    private static func isTitleBarArea(_ element: AXUIElement) -> Bool {
        let role = attribute(of: element, key: kAXRoleAttribute) as? String
        let subrole = attribute(of: element, key: kAXSubroleAttribute) as? String

        // Direct title bar subrole
        if subrole == "AXTitleBar" { return true }

        // Window control buttons that live in the title bar
        let titleBarSubroles: Set<String> = [
            "AXCloseButton",
            "AXMinimizeButton",
            "AXZoomButton",
            "AXToolbarButton",
            "AXFullScreenButton"
        ]
        if let subrole, titleBarSubroles.contains(subrole) { return true }

        // Toolbar role (macOS unified title bar + toolbar)
        if role == "AXToolbar" { return true }

        // Title bar group or static text inside the title bar
        if role == "AXGroup" || role == "AXStaticText" || role == "AXImage" {
            // Check if a parent is the title bar or toolbar
            if let parent = attribute(of: element, key: kAXParentAttribute) {
                let parentRole = attribute(of: parent as! AXUIElement, key: kAXRoleAttribute) as? String
                let parentSubrole = attribute(of: parent as! AXUIElement, key: kAXSubroleAttribute) as? String
                if parentSubrole == "AXTitleBar" || parentRole == "AXToolbar" {
                    return true
                }
            }
        }

        return false
    }

    private static func findWindow(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        while let el = current {
            let role = attribute(of: el, key: kAXRoleAttribute) as? String
            if role == "AXWindow" {
                return el
            }
            current = attribute(of: el, key: kAXParentAttribute) as! AXUIElement?
        }
        return nil
    }

    private static func attribute(of element: AXUIElement, key: String) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard error == .success else { return nil }
        return value
    }
}
