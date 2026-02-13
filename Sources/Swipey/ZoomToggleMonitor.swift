import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "zoom-toggle")

/// Left Cmd keycode
private let kLeftCmdKeycode: Int64 = 0x37
/// Right Cmd keycode
private let kRightCmdKeycode: Int64 = 0x36

final class ZoomToggleMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = ZoomToggleStateMachine()

    /// Called when double-Cmd is detected (expand/toggle).
    var onActivated: (() -> Void)?
    /// Called when hold-release is detected (collapse).
    var onHoldReleased: (() -> Void)?

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        // Listen for flagsChanged (modifier keys) and keyDown (to detect non-modifier keys)
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ZoomToggleMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)  // always pass through — never consume keyboard events
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,  // tail append — observe only, don't block
            options: .listenOnly,         // listen only — we never consume keyboard events
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create zoom toggle event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.warning("[Swipey] Zoom toggle monitor started")
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

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let timestamp = CFAbsoluteTimeGetCurrent()

        // Non-modifier key pressed — reset sequence
        if type == .keyDown {
            _ = stateMachine.feed(.nonModifierKey, at: timestamp)
            return
        }

        guard type == .flagsChanged else { return }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let input: ZoomToggleStateMachine.Input
        switch keycode {
        case kLeftCmdKeycode:
            input = flags.contains(.maskCommand) ? .cmdDown(.left) : .cmdUp(.left)
        case kRightCmdKeycode:
            input = flags.contains(.maskCommand) ? .cmdDown(.right) : .cmdUp(.right)
        default:
            return  // not a Cmd key
        }

        if let output = stateMachine.feed(input, at: timestamp) {
            switch output {
            case .activated:
                logger.warning("[Swipey] Double-Cmd detected — toggling zoom")
                onActivated?()
            case .holdReleased:
                logger.warning("[Swipey] Hold released — collapsing zoom")
                onHoldReleased?()
            }
        }
    }

    deinit {
        stop()
    }
}
