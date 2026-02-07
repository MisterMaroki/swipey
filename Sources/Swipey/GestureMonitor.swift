import CoreGraphics
import ApplicationServices
import AppKit

final class GestureMonitor: @unchecked Sendable {
    private let windowManager: WindowManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var stateMachine = GestureStateMachine()
    private var trackedWindow: AXUIElement?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<GestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[Swipey] Failed to create event tap — accessibility permission required.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Swipey] Gesture monitor started.")
    }

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap is disabled by the system, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Only handle trackpad (continuous) scroll events
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        guard isContinuous != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)

        // Raw deltas from the event (pixel-based for trackpad)
        let rawDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let rawDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

        // We want deltas to match the physical finger movement direction.
        // With natural scrolling enabled, the system inverts deltas (content follows finger),
        // so raw negative deltaY means fingers moved UP — which is what we want.
        // With natural scrolling disabled, negative deltaY means scroll up (content moves up),
        // which also corresponds to fingers moving up on the trackpad.
        // Either way, negative deltaY = swipe up, negative deltaX = swipe left.
        let deltaX = rawDeltaX
        let deltaY = rawDeltaY

        switch phase {
        case 1: // NSEventPhase.began
            handleBegan(deltaX: deltaX, deltaY: deltaY, event: event)
        case 2, 4: // NSEventPhase.stationary, .changed
            handleChanged(deltaX: deltaX, deltaY: deltaY)
        case 8: // NSEventPhase.ended
            handleEnded()
        case 16: // NSEventPhase.cancelled
            handleCancelled()
        default:
            break
        }

        // If we're actively tracking a gesture, consume the event so it doesn't scroll
        if trackedWindow != nil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleBegan(deltaX: Double, deltaY: Double, event: CGEvent) {
        // Get cursor position from the event (CG coordinates, top-left origin)
        let mouseLocation = event.location

        // Check if cursor is over a title bar
        if let window = TitleBarDetector.detectWindow(at: mouseLocation) {
            trackedWindow = window
            stateMachine.begin()
            stateMachine.feed(deltaX: deltaX, deltaY: deltaY)
        }
    }

    private func handleChanged(deltaX: Double, deltaY: Double) {
        guard trackedWindow != nil else { return }
        stateMachine.feed(deltaX: deltaX, deltaY: deltaY)
    }

    private func handleEnded() {
        defer {
            stateMachine.reset()
            trackedWindow = nil
        }

        guard let window = trackedWindow,
              let position = stateMachine.resolvedPosition else { return }

        windowManager.tile(window: window, to: position)
    }

    private func handleCancelled() {
        stateMachine.reset()
        trackedWindow = nil
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}
