@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "com.swipey.app", category: "grid-resize")

final class GridResizeManager: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: DispatchSourceTimer?
    private var snapshot: GridSnapshot?
    private var windowElements: [Int: AXUIElement] = [:]  // window id -> AXUIElement

    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start() {
        if let existingTap = eventTap {
            if CGEvent.tapIsEnabled(tap: existingTap) { return }
            stop()
        }

        let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<GridResizeManager>.fromOpaque(userInfo).takeUnretainedValue()
            manager.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)  // never consume — pass through
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.warning("[Swipey] Failed to create grid resize event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("[Swipey] Grid resize monitor started")
    }

    func stop() {
        stopPolling()
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

        guard type == .flagsChanged else { return }

        let flags = event.flags
        if flags.contains(.maskControl) {
            // Ctrl pressed — build snapshot and start polling
            if snapshot == nil {
                startGridSession()
            }
        } else {
            // Ctrl released — stop polling
            if snapshot != nil {
                stopPolling()
            }
        }
    }

    // MARK: - Grid Session

    private func startGridSession() {
        let windows = discoverTiledWindows()
        guard windows.count >= 2 else {
            logger.debug("[Swipey] Grid resize: fewer than 2 tiled windows, skipping")
            return
        }

        // Get screen frame for the screen under the cursor
        let mouseLocation = NSEvent.mouseLocation
        guard let mainScreen = NSScreen.screens.first else { return }
        let cgMouseY = mainScreen.frame.height - mouseLocation.y
        let cgMouse = CGPoint(x: mouseLocation.x, y: cgMouseY)

        let screen = NSScreen.screens.first(where: { screen in
            let cgScreenOrigin = CGPoint(x: screen.frame.origin.x, y: mainScreen.frame.height - screen.frame.maxY)
            let cgScreenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)
            return cgScreenFrame.contains(cgMouse)
        }) ?? mainScreen

        let cgScreenOrigin = CGPoint(x: screen.frame.origin.x, y: mainScreen.frame.height - screen.frame.maxY)
        let screenFrame = CGRect(origin: cgScreenOrigin, size: screen.frame.size)

        var windowEntries: [(id: Int, frame: CGRect)] = []
        windowElements = [:]
        for (axElement, frame) in windows {
            let key = Int(CFHash(axElement))
            windowEntries.append((id: key, frame: frame))
            windowElements[key] = axElement
        }

        snapshot = GridSnapshot(windows: windowEntries, screenFrame: screenFrame)

        guard let snap = snapshot, !snap.sharedEdges.isEmpty else {
            logger.debug("[Swipey] Grid resize: no shared edges found")
            snapshot = nil
            windowElements = [:]
            return
        }

        logger.info("[Swipey] Grid resize: found \(snap.sharedEdges.count) shared edge(s) across \(snap.windows.count) windows")
        startPolling()
    }

    // MARK: - Window Discovery

    /// Find all windows on screen and return their AXUIElement + CG frame.
    private func discoverTiledWindows() -> [(AXUIElement, CGRect)] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [(AXUIElement, CGRect)] = []

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0  // normal window layer only
            else { continue }

            guard let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }

            let frame = CGRect(x: x, y: y, width: w, height: h)

            // Skip tiny windows (menu bar items, etc.)
            guard w > 100 && h > 100 else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

            // Match CG window bounds to AX window
            for axWindow in axWindows {
                if let axFrame = getFrame(of: axWindow),
                   abs(axFrame.origin.x - x) < 2 && abs(axFrame.origin.y - y) < 2 &&
                   abs(axFrame.width - w) < 2 && abs(axFrame.height - h) < 2 {
                    results.append((axWindow, frame))
                    break
                }
            }
        }

        return results
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))  // ~60Hz
        timer.setEventHandler { [weak self] in
            self?.pollWindowFrames()
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
        snapshot = nil
        windowElements = [:]
        logger.debug("[Swipey] Grid resize: session ended")
    }

    private func pollWindowFrames() {
        guard var snap = snapshot else { return }

        // Clear adjusting flags from previous cycle
        for entry in snap.windows {
            if entry.isAdjusting {
                snap.setAdjusting(false, forWindow: entry.id)
            }
        }

        for entry in snap.windows {
            guard let axElement = windowElements[entry.id],
                  let currentFrame = getFrame(of: axElement) else {
                // Window gone — remove it
                continue
            }

            let oldFrame = entry.frame
            guard !framesEqual(oldFrame, currentFrame) else { continue }

            // Frame changed
            snap.updateFrame(forWindow: entry.id, newFrame: currentFrame)

            if entry.isAdjusting {
                // This was our own adjustment — skip propagation
                continue
            }

            let adjustments = snap.computePropagation(
                changedWindowId: entry.id,
                oldFrame: oldFrame,
                newFrame: currentFrame
            )

            for adj in adjustments {
                guard let adjElement = windowElements[adj.windowId] else { continue }
                setFrame(of: adjElement, to: adj.newFrame)
                snap.updateFrame(forWindow: adj.windowId, newFrame: adj.newFrame)
                snap.setAdjusting(true, forWindow: adj.windowId)
            }
        }

        snapshot = snap
    }

    // MARK: - AX Helpers

    private func getFrame(of window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              let axPos = posValue as! AXValue? else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axPos, .cgPoint, &point) else { return nil }

        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let axSize = sizeValue as! AXValue? else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axSize, .cgSize, &size) else { return nil }

        return CGRect(origin: point, size: size)
    }

    private func setFrame(of window: AXUIElement, to frame: CGRect) {
        var point = frame.origin
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func framesEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.origin.x - b.origin.x) < 0.5
            && abs(a.origin.y - b.origin.y) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    deinit {
        stop()
    }
}
