import ApplicationServices
import AppKit

final class WindowManager {
    func tile(window: AXUIElement, to position: TilePosition) {
        // Determine which screen the window is currently on
        guard let screen = screen(for: window) else { return }

        // Calculate target frame in NSScreen coordinates (bottom-left origin)
        let nsFrame = position.frame(for: screen)

        // Convert to CG/Accessibility coordinates (top-left origin)
        guard let mainScreen = NSScreen.screens.first else { return }
        let cgOrigin = CGPoint(
            x: nsFrame.origin.x,
            y: mainScreen.frame.height - nsFrame.origin.y - nsFrame.height
        )

        // Set position first, then size (some apps need this order)
        setPosition(of: window, to: cgOrigin)
        setSize(of: window, to: nsFrame.size)
    }

    // MARK: - Private

    private func screen(for window: AXUIElement) -> NSScreen? {
        guard let position = getPosition(of: window) else {
            return NSScreen.main
        }

        // position is in CG coordinates (top-left origin)
        // Convert to NSScreen coordinates for containsPoint check
        guard let mainScreen = NSScreen.screens.first else { return NSScreen.main }
        let nsPoint = CGPoint(x: position.x, y: mainScreen.frame.height - position.y)

        for screen in NSScreen.screens {
            if screen.frame.contains(nsPoint) {
                return screen
            }
        }

        return NSScreen.main
    }

    private func getPosition(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success, let axValue = value else { return nil }

        // AXValue is bridged as AnyObject; cast to AXValue
        let typedValue = axValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func setPosition(of window: AXUIElement, to point: CGPoint) {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setSize(of window: AXUIElement, to size: CGSize) {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}
