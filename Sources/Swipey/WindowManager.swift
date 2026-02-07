@preconcurrency import ApplicationServices
import AppKit

final class WindowManager: @unchecked Sendable {
    /// Saved frames for restore (keyed by window hash).
    private var savedFrames: [Int: CGRect] = [:]

    func tile(window: AXUIElement, to position: TilePosition, on targetScreen: NSScreen? = nil) {
        let screen = targetScreen ?? screen(for: window) ?? NSScreen.main!

        switch position {
        case .fullscreen:
            saveFrame(for: window)
            enterFullscreen(window: window)
            return

        case .restore:
            restoreFrame(for: window)
            return

        default:
            break
        }

        // Save frame before tiling (for future restore)
        saveFrame(for: window)

        let nsFrame = position.frame(for: screen)
        guard let mainScreen = NSScreen.screens.first else { return }
        let cgOrigin = CGPoint(
            x: nsFrame.origin.x,
            y: mainScreen.frame.height - nsFrame.origin.y - nsFrame.height
        )
        let targetSize = nsFrame.size

        // Animate the window to the target position
        animateTile(window: window, to: cgOrigin, size: targetSize)
    }

    // MARK: - Fullscreen

    private func enterFullscreen(window: AXUIElement) {
        // Try setting AXFullScreen attribute
        let result = AXUIElementSetAttributeValue(
            window,
            "AXFullScreen" as CFString,
            kCFBooleanTrue
        )
        if result != .success {
            // Fallback: press the zoom button
            var zoomButton: AnyObject?
            let err = AXUIElementCopyAttributeValue(window, "AXZoomButton" as CFString, &zoomButton)
            if err == .success, let button = zoomButton {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }
    }

    // MARK: - Save / Restore

    private func windowKey(for window: AXUIElement) -> Int {
        // Use the AXUIElement's hash as a stable key
        return Int(CFHash(window))
    }

    private func saveFrame(for window: AXUIElement) {
        let key = windowKey(for: window)
        // Don't overwrite if already saved (preserves the original pre-tile frame)
        guard savedFrames[key] == nil else { return }
        guard let position = getPosition(of: window),
              let size = getSize(of: window) else { return }
        savedFrames[key] = CGRect(origin: position, size: size)
    }

    private func restoreFrame(for window: AXUIElement) {
        let key = windowKey(for: window)

        // Check if window is in native fullscreen first
        var fullscreenValue: AnyObject?
        let fsErr = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
        if fsErr == .success, let isFS = fullscreenValue as? Bool, isFS {
            // Exit native fullscreen
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            // Remove saved frame since we're restoring from fullscreen
            savedFrames.removeValue(forKey: key)
            return
        }

        guard let savedFrame = savedFrames[key] else { return }
        savedFrames.removeValue(forKey: key)
        animateTile(window: window, to: savedFrame.origin, size: savedFrame.size)
    }

    // MARK: - Animation

    private func animateTile(window: AXUIElement, to targetOrigin: CGPoint, size targetSize: CGSize) {
        let steps = 8
        let intervalMicroseconds: useconds_t = useconds_t(200_000 / UInt32(steps))

        guard let startPos = getPosition(of: window),
              let startSize = getSize(of: window) else {
            setPosition(of: window, to: targetOrigin)
            setSize(of: window, to: targetSize)
            return
        }

        // Run animation on a background thread to avoid sendability issues.
        // AXUIElement calls are thread-safe.
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let eased = 1.0 - pow(1.0 - t, 3)

                let x = startPos.x + (targetOrigin.x - startPos.x) * eased
                let y = startPos.y + (targetOrigin.y - startPos.y) * eased
                let w = startSize.width + (targetSize.width - startSize.width) * eased
                let h = startSize.height + (targetSize.height - startSize.height) * eased

                self.setPosition(of: window, to: CGPoint(x: x, y: y))
                self.setSize(of: window, to: CGSize(width: w, height: h))

                if i < steps {
                    usleep(intervalMicroseconds)
                }
            }

            // Ensure exact final position
            self.setPosition(of: window, to: targetOrigin)
            self.setSize(of: window, to: targetSize)
        }
    }

    // MARK: - Screen detection

    func screen(for window: AXUIElement) -> NSScreen? {
        guard let position = getPosition(of: window) else {
            return NSScreen.main
        }

        guard let mainScreen = NSScreen.screens.first else { return NSScreen.main }
        let nsPoint = CGPoint(x: position.x, y: mainScreen.frame.height - position.y)

        for screen in NSScreen.screens {
            if screen.frame.contains(nsPoint) {
                return screen
            }
        }

        return NSScreen.main
    }

    /// Determine which screen contains the given CG point (top-left origin).
    func screen(at cgPoint: CGPoint) -> NSScreen? {
        guard let mainScreen = NSScreen.screens.first else { return NSScreen.main }
        let nsPoint = CGPoint(x: cgPoint.x, y: mainScreen.frame.height - cgPoint.y)

        for screen in NSScreen.screens {
            if screen.frame.contains(nsPoint) {
                return screen
            }
        }
        return NSScreen.main
    }

    // MARK: - AX helpers

    private func getPosition(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success, let axValue = value else { return nil }
        let typedValue = axValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func getSize(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard error == .success, let axValue = value else { return nil }
        let typedValue = axValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(typedValue, .cgSize, &size) else { return nil }
        return size
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
