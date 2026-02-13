@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "zoom")

final class ZoomManager: @unchecked Sendable {
    private let windowManager: WindowManager

    /// Tracks zoomed windows: windowKey -> (originalTileFrame in NS coords, tilePosition)
    private var zoomedWindows: [Int: ZoomState] = [:]

    struct ZoomState {
        /// The original tile frame in NS coordinates (before zoom expansion).
        let tileFrame: CGRect
        /// The tile position for anchor calculation.
        let position: TilePosition
        /// The screen the window is on.
        let screen: NSScreen
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    /// Toggle zoom on the currently focused window.
    func toggleFocusedWindow() {
        let appElement = AXUIElementCreateApplication(focusedAppPID())

        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard err == .success, let window = focusedValue else { return }

        let axWindow = window as! AXUIElement
        let key = Int(CFHash(axWindow))

        if let state = zoomedWindows[key] {
            collapse(window: axWindow, to: state)
            zoomedWindows.removeValue(forKey: key)
        } else {
            expand(window: axWindow, key: key)
        }
    }

    /// Collapse the focused window (hold-release mode).
    func collapseFocusedWindow() {
        let appElement = AXUIElementCreateApplication(focusedAppPID())

        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard err == .success, let window = focusedValue else { return }

        let axWindow = window as! AXUIElement
        let key = Int(CFHash(axWindow))

        if let state = zoomedWindows[key] {
            collapse(window: axWindow, to: state)
            zoomedWindows.removeValue(forKey: key)
        }
    }

    /// Call this when a window is re-tiled via gesture to clear its zoom state.
    func clearZoomState(for window: AXUIElement) {
        let key = Int(CFHash(window))
        zoomedWindows.removeValue(forKey: key)
    }

    /// Whether the given window is currently zoomed.
    func isZoomed(_ window: AXUIElement) -> Bool {
        let key = Int(CFHash(window))
        return zoomedWindows[key] != nil
    }

    /// Accessory apps may not appear as `frontmostApplication`.
    /// When our own app is active, use our PID directly.
    private func focusedAppPID() -> pid_t {
        if NSRunningApplication.current.isActive {
            return ProcessInfo.processInfo.processIdentifier
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? ProcessInfo.processInfo.processIdentifier
    }

    // MARK: - Private

    private func expand(window: AXUIElement, key: Int) {
        guard let screen = windowManager.screen(for: window) else { return }

        // Determine current tile position by matching the window frame
        guard let position = detectTilePosition(of: window, on: screen) else { return }

        let tileFrame = position.frame(for: screen)
        let expandedFrame = ZoomFrameCalculator.expandedFrame(
            tileFrame: tileFrame,
            position: position,
            visibleFrame: screen.visibleFrame
        )

        zoomedWindows[key] = ZoomState(tileFrame: tileFrame, position: position, screen: screen)

        // Convert from NS coordinates to CG coordinates for AX
        windowManager.animateToNSFrame(window: window, frame: expandedFrame)

        logger.info("[Swipey] Expanded \(String(describing: position)) window")
    }

    private func collapse(window: AXUIElement, to state: ZoomState) {
        windowManager.animateToNSFrame(window: window, frame: state.tileFrame)
        logger.info("[Swipey] Collapsed window back to \(String(describing: state.position))")
    }

    /// Try to match the window's current frame to a known tile position.
    private func detectTilePosition(of window: AXUIElement, on screen: NSScreen) -> TilePosition? {
        guard let cgPos = windowManager.getWindowPosition(window),
              let cgSize = windowManager.getWindowSize(window) else { return nil }

        // Convert CG position (top-left origin) to NS position (bottom-left origin)
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let nsOrigin = CGPoint(x: cgPos.x, y: mainScreen.frame.height - cgPos.y - cgSize.height)
        let windowFrame = CGRect(origin: nsOrigin, size: cgSize)

        let candidates: [TilePosition] = [
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        ]

        for position in candidates {
            let tileFrame = position.frame(for: screen)
            if framesMatch(windowFrame, tileFrame, tolerance: 10) {
                return position
            }
        }

        return nil
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
