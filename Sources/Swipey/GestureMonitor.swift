import CoreGraphics
import ApplicationServices
import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "gesture")

final class GestureMonitor: @unchecked Sendable {
    private let windowManager: WindowManager
    private let previewOverlay: PreviewOverlay
    private let cursorIndicator: CursorIndicator
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var stateMachine = GestureStateMachine()
    private var trackedWindow: AXUIElement?
    private var targetScreen: NSScreen?
    private var lastResolvedPosition: TilePosition?
    private var trackedWindowIsFullscreen = false
    private var cursorLocation: CGPoint = .zero

    /// Cooldown: ignore new gestures for a short period after tiling.
    private var cooldownUntil: CFAbsoluteTime = 0
    private let cooldownDuration: CFAbsoluteTime = 0.3

    /// Cancel gesture if fingers stay still for this long.
    private var cancelWarningTimer: DispatchWorkItem?
    private var inactivityTimer: DispatchWorkItem?
    private var showingCancelPreview = false
    private let cancelWarningDelay: TimeInterval = 2.0
    private let inactivityTimeout: TimeInterval = 3.0

    init(windowManager: WindowManager, previewOverlay: PreviewOverlay, cursorIndicator: CursorIndicator) {
        self.windowManager = windowManager
        self.previewOverlay = previewOverlay
        self.cursorIndicator = cursorIndicator
    }

    /// Try to create the event tap. Call again later if accessibility isn't granted yet.
    func start() {
        // If we have an existing tap, check if it's actually enabled
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) {
                return // Already running fine
            }
            // Tap exists but is disabled — tear it down and recreate
            logger.warning("[Swipey] Existing tap disabled, recreating...")
            stop()
        }

        let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<GestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
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
            logger.warning("[Swipey] Failed to create event tap — waiting for accessibility permission.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        let enabled = CGEvent.tapIsEnabled(tap: tap)
        logger.warning("[Swipey] Gesture monitor started. Tap enabled: \(enabled)")
    }

    /// Whether the event tap is active and enabled.
    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Tear down the event tap.
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

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Ignore non-scroll events (mouse moved used only for diagnostic)
        guard type == .scrollWheel || type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else {
            return Unmanaged.passUnretained(event)
        }

        // If the tap is disabled by the system, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let deltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

        // Skip momentum/inertia events
        guard momentumPhase == 0 else {
            if trackedWindow != nil { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard isContinuous != 0 else {
            return Unmanaged.passUnretained(event)
        }

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
        if CFAbsoluteTimeGetCurrent() < cooldownUntil {
            return
        }

        let mouseLocation = event.location
        targetScreen = windowManager.screen(at: mouseLocation)

        if let window = TitleBarDetector.detectWindow(at: mouseLocation) {
            trackedWindow = window
            trackedWindowIsFullscreen = Self.isFullscreen(window)
            lastResolvedPosition = nil
            cursorLocation = mouseLocation
            stateMachine.begin()
            stateMachine.feed(deltaX: deltaX, deltaY: deltaY)
            checkAndShowPreview()
            scheduleInactivityTimer()
        }
    }

    private func handleChanged(deltaX: Double, deltaY: Double) {
        guard trackedWindow != nil else { return }

        let wasShowingCancel = showingCancelPreview
        scheduleInactivityTimer()

        let previousPosition = stateMachine.resolvedPosition
        stateMachine.feed(deltaX: deltaX, deltaY: deltaY)

        let currentPosition = stateMachine.resolvedPosition

        if wasShowingCancel {
            // Recover from cancel preview — re-show indicators
            if let position = currentPosition, let screen = targetScreen {
                let loc = cursorLocation
                let nsFrame = position.needsFrame ? position.frame(for: screen) : nil
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let nsFrame {
                        self.previewOverlay.show(frame: nsFrame, on: screen)
                    }
                    self.cursorIndicator.update(position: position, at: loc)
                    self.lastResolvedPosition = position
                }
            }
        } else if currentPosition != previousPosition {
            if currentPosition != nil {
                checkAndShowPreview()
            }
        }
    }

    private func handleEnded() {
        let wasCancelShowing = showingCancelPreview
        cancelInactivityTimer()
        let position = wasCancelShowing ? nil : stateMachine.resolvedPosition
        let window = trackedWindow
        let screen = targetScreen

        DispatchQueue.main.async { [weak self] in
            self?.previewOverlay.hide()
            self?.cursorIndicator.hide()
        }

        defer {
            stateMachine.reset()
            trackedWindow = nil
            trackedWindowIsFullscreen = false
            targetScreen = nil
            lastResolvedPosition = nil
        }

        guard let window else {
            return
        }

        // Fullscreen windows: exit fullscreen, then tile to resolved position
        if trackedWindowIsFullscreen {
            cooldownUntil = CFAbsoluteTimeGetCurrent() + cooldownDuration
            let tilePosition = position ?? .restore
            logger.warning("[Swipey] exiting fullscreen → \(String(describing: tilePosition))")
            windowManager.exitFullscreenAndTile(window: window, to: tilePosition, on: screen)
            return
        }

        guard let position else {
            return
        }

        cooldownUntil = CFAbsoluteTimeGetCurrent() + cooldownDuration

        logger.warning("[Swipey] tiling to \(String(describing: position))")
        windowManager.tile(window: window, to: position, on: screen)
    }

    private func handleCancelled() {
        cancelInactivityTimer()
        DispatchQueue.main.async { [weak self] in
            self?.previewOverlay.hide()
            self?.cursorIndicator.hide()
        }
        stateMachine.reset()
        trackedWindow = nil
        trackedWindowIsFullscreen = false
        targetScreen = nil
        lastResolvedPosition = nil
    }

    // MARK: - Fullscreen detection

    private static func isFullscreen(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        if err == .success, let isFS = value as? Bool, isFS {
            return true
        }
        return false
    }

    // MARK: - Inactivity timer

    private func scheduleInactivityTimer() {
        cancelWarningTimer?.cancel()
        inactivityTimer?.cancel()
        showingCancelPreview = false

        // Show cancel preview after warning delay
        let warning = DispatchWorkItem { [weak self] in
            guard let self, self.trackedWindow != nil else { return }
            self.showingCancelPreview = true
            DispatchQueue.main.async { [weak self] in
                self?.previewOverlay.hide()
                self?.cursorIndicator.showCancel()
            }
        }
        cancelWarningTimer = warning
        DispatchQueue.main.asyncAfter(deadline: .now() + cancelWarningDelay, execute: warning)

        // Full cancel after timeout
        let cancel = DispatchWorkItem { [weak self] in
            guard let self, self.trackedWindow != nil else { return }
            logger.warning("[Swipey] Gesture cancelled due to inactivity")
            self.handleCancelled()
        }
        inactivityTimer = cancel
        DispatchQueue.main.asyncAfter(deadline: .now() + inactivityTimeout, execute: cancel)
    }

    private func cancelInactivityTimer() {
        cancelWarningTimer?.cancel()
        cancelWarningTimer = nil
        inactivityTimer?.cancel()
        inactivityTimer = nil
        showingCancelPreview = false
    }

    // MARK: - Preview

    private func checkAndShowPreview() {
        guard let position = stateMachine.resolvedPosition,
              let screen = targetScreen else {
            return
        }

        let newPosition = position
        let loc = cursorLocation

        if position.needsFrame {
            let nsFrame = position.frame(for: screen)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.lastResolvedPosition?.needsFrame == true {
                    self.previewOverlay.update(frame: nsFrame)
                } else {
                    self.previewOverlay.show(frame: nsFrame, on: screen)
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Hide preview if transitioning to a non-frame position
            if !newPosition.needsFrame && (self.lastResolvedPosition?.needsFrame ?? false) {
                self.previewOverlay.hide()
            }

            if self.lastResolvedPosition == nil {
                self.cursorIndicator.show(position: newPosition, at: loc)
            } else {
                self.cursorIndicator.update(position: newPosition, at: loc)
            }
            self.lastResolvedPosition = newPosition
        }
    }

    deinit {
        stop()
    }
}
