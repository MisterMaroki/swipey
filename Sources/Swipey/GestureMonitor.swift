import CoreGraphics
import ApplicationServices
import AppKit

final class GestureMonitor: @unchecked Sendable {
    private let windowManager: WindowManager
    private let previewOverlay: PreviewOverlay
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var stateMachine = GestureStateMachine()
    private var trackedWindow: AXUIElement?
    private var targetScreen: NSScreen?
    private var lastResolvedPosition: TilePosition?

    /// Cooldown: ignore new gestures for a short period after tiling.
    private var cooldownUntil: CFAbsoluteTime = 0
    private let cooldownDuration: CFAbsoluteTime = 0.3

    init(windowManager: WindowManager, previewOverlay: PreviewOverlay) {
        self.windowManager = windowManager
        self.previewOverlay = previewOverlay
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
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        // Skip momentum/inertia events
        guard momentumPhase == 0 else {
            // If we're tracking, consume momentum events too
            if trackedWindow != nil { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard isContinuous != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let deltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

        switch phase {
        case 1: // began
            handleBegan(deltaX: deltaX, deltaY: deltaY, event: event)
        case 2: // changed
            handleChanged(deltaX: deltaX, deltaY: deltaY)
        case 4: // ended
            handleEnded()
        case 8, 16: // cancelled
            handleCancelled()
        default:
            break
        }

        // If we're actively tracking a gesture, consume the event
        if trackedWindow != nil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleBegan(deltaX: Double, deltaY: Double, event: CGEvent) {
        // Check cooldown
        if CFAbsoluteTimeGetCurrent() < cooldownUntil {
            return
        }

        let mouseLocation = event.location

        // Determine target screen from cursor position
        targetScreen = windowManager.screen(at: mouseLocation)

        if let window = TitleBarDetector.detectWindow(at: mouseLocation) {
            trackedWindow = window
            lastResolvedPosition = nil
            stateMachine.begin()
            stateMachine.feed(deltaX: deltaX, deltaY: deltaY)
            checkAndShowPreview()
        }
    }

    private func handleChanged(deltaX: Double, deltaY: Double) {
        guard trackedWindow != nil else { return }

        let previousPosition = stateMachine.resolvedPosition
        stateMachine.feed(deltaX: deltaX, deltaY: deltaY)

        let currentPosition = stateMachine.resolvedPosition

        // Update preview if position changed
        if currentPosition != previousPosition {
            if currentPosition != nil {
                checkAndShowPreview()
            }
        }
    }

    private func handleEnded() {
        let position = stateMachine.resolvedPosition
        let window = trackedWindow
        let screen = targetScreen

        // Hide preview
        DispatchQueue.main.async { [weak self] in
            self?.previewOverlay.hide()
        }

        defer {
            stateMachine.reset()
            trackedWindow = nil
            targetScreen = nil
            lastResolvedPosition = nil
        }

        guard let window, let position else {
            return
        }

        // Set cooldown
        cooldownUntil = CFAbsoluteTimeGetCurrent() + cooldownDuration

        print("[Swipey] tiling to \(position)")
        windowManager.tile(window: window, to: position, on: screen)
    }

    private func handleCancelled() {
        DispatchQueue.main.async { [weak self] in
            self?.previewOverlay.hide()
        }
        stateMachine.reset()
        trackedWindow = nil
        targetScreen = nil
        lastResolvedPosition = nil
    }

    // MARK: - Preview

    private func checkAndShowPreview() {
        guard let position = stateMachine.resolvedPosition,
              let screen = targetScreen,
              position.needsFrame else {
            return
        }

        let nsFrame = position.frame(for: screen)
        let newPosition = position

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lastResolvedPosition == nil {
                self.previewOverlay.show(frame: nsFrame, on: screen)
            } else {
                self.previewOverlay.update(frame: nsFrame)
            }
            self.lastResolvedPosition = newPosition
        }
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
