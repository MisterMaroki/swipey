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

        // If hit test returns the window itself, cursor is on the non-content
        // area (title bar / window frame)
        if role == kAXWindowRole as String { return true }
        if subrole == "AXTitleBar" { return true }

        // Window control buttons
        let titleBarSubroles: Set<String> = [
            "AXCloseButton", "AXMinimizeButton", "AXZoomButton",
            "AXToolbarButton", "AXFullScreenButton"
        ]
        if let subrole, titleBarSubroles.contains(subrole) { return true }

        // Toolbar role
        if role == "AXToolbar" { return true }

        // Walk up ancestors to check if any parent is a title bar, toolbar, or window
        var current = element
        for _ in 0..<5 {
            guard let parent = attribute(of: current, key: kAXParentAttribute) as! AXUIElement? else {
                break
            }
            let parentRole = attribute(of: parent, key: kAXRoleAttribute) as? String
            let parentSubrole = attribute(of: parent, key: kAXSubroleAttribute) as? String

            if parentSubrole == "AXTitleBar" || parentRole == "AXToolbar" {
                return true
            }
            // If parent is a window, the element is a direct child of the window
            // (title text, groups, etc. in the title bar area)
            if parentRole == kAXWindowRole as String {
                return true
            }
            current = parent
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
