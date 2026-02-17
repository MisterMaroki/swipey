import CoreGraphics
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "keyboard-tile")

/// Arrow key keycodes
private let kLeftArrow: Int64 = 0x7B
private let kRightArrow: Int64 = 0x7C
private let kDownArrow: Int64 = 0x7D
private let kUpArrow: Int64 = 0x7E

/// Required modifier flags: Ctrl + Option, without Cmd or Shift
private let kRequiredFlags: CGEventFlags = [.maskControl, .maskAlternate]
private let kExcludedFlags: CGEventFlags = [.maskCommand, .maskShift]

final class KeyboardTileMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let windowManager: WindowManager

    /// Called after a window is tiled via keyboard shortcut.
    var onWindowTiled: ((AXUIElement) -> Void)?

    /// Called with the tile position when a keyboard tile is performed.
    var onTileAction: ((TilePosition) -> Void)?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardTileMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create keyboard tile event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("[Swipey] Keyboard tile monitor started")
    }

    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // Check modifiers: require Ctrl+Option, reject if Cmd or Shift also held
        let flags = event.flags
        guard flags.contains(kRequiredFlags),
              flags.isDisjoint(with: kExcludedFlags) else {
            return Unmanaged.passUnretained(event)
        }

        // Map keycode to arrow direction
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let direction: KeyboardTileStateMachine.ArrowDirection
        switch keycode {
        case kLeftArrow:  direction = .left
        case kRightArrow: direction = .right
        case kDownArrow:  direction = .down
        case kUpArrow:    direction = .up
        default:
            return Unmanaged.passUnretained(event)
        }

        // Get the focused window
        guard let window = focusedWindow() else {
            return Unmanaged.passUnretained(event)
        }

        // Detect current tile position
        let windowScreen = windowManager.screen(for: window)
        let currentPosition: TilePosition?
        if windowManager.isFullscreen(window) {
            currentPosition = .fullscreen
        } else if let screen = windowScreen {
            currentPosition = windowManager.detectTilePosition(of: window, on: screen)
        } else {
            currentPosition = nil
        }

        // Run state machine
        guard let targetPosition = KeyboardTileStateMachine.transition(
            from: currentPosition, direction: direction
        ) else {
            return Unmanaged.passUnretained(event)  // no-op, pass through
        }

        let screen = windowScreen ?? NSScreen.main

        // Handle fullscreen exit specially
        if currentPosition == .fullscreen {
            windowManager.exitFullscreenAndTile(window: window, to: targetPosition, on: screen)
        } else {
            windowManager.tile(window: window, to: targetPosition, on: screen)
        }

        onWindowTiled?(window)
        onTileAction?(targetPosition)

        logger.info("[Swipey] Keyboard tile: \(String(describing: currentPosition)) → \(String(describing: targetPosition))")

        return nil  // consume the event
    }

    private func focusedWindow() -> AXUIElement? {
        let pid: pid_t
        if NSRunningApplication.current.isActive {
            pid = ProcessInfo.processInfo.processIdentifier
        } else {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            pid = app.processIdentifier
        }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedValue
        )
        guard err == .success, let value = focusedValue else { return nil }
        return (value as! AXUIElement)
    }

    deinit {
        stop()
    }
}
