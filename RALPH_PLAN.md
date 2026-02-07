# Swipey - Ralph Execution Plan

A lightweight macOS app for two-finger swipe window tiling.

---

## Phase 1: Core Foundation

```
<background>
You are an expert macOS/Swift developer building a lightweight window tiling app called Swipey. The app runs as a menu bar agent (no dock icon). When the user places their cursor on any window's title bar and performs a two-finger trackpad swipe, the window tiles to a preset position.

Tech stack: Swift, AppKit, Swift Package Manager (executable target). Target macOS 14+. The project directory is /Users/omarmaroki/Projects/swipey and is currently empty.

Core gesture mappings for this phase:
- Two-finger swipe UP on title bar -> maximize window (fill screen with small margin)
- Two-finger swipe LEFT on title bar -> tile to left half
- Two-finger swipe RIGHT on title bar -> tile to right half

Architecture overview:
- AppDelegate: NSApplicationDelegate, app lifecycle, LSUIElement for menu bar agent
- StatusBarController: NSStatusItem with menu (Quit + accessibility status)
- AccessibilityManager: Check/request AXIsProcessTrusted permissions
- GestureMonitor: CGEventTap intercepting .scrollWheel events globally
- TitleBarDetector: AXUIElement hit-test to check if cursor is over a window title bar
- GestureStateMachine: Tracks cumulative deltaX/deltaY, dead zone, direction resolution
- TilePosition: Enum for tile targets (maximize, leftHalf, rightHalf)
- WindowManager: Move/resize windows via AXUIElement (AXPosition, AXSize attributes)
</background>

<setup>
1. Initialize a git repository in /Users/omarmaroki/Projects/swipey with git init.
2. Research CGEventTap API usage for intercepting trackpad scroll events in Swift. Understand how to create an event tap, the callback signature, and how to distinguish trackpad scroll (continuous) from mouse scroll (line-based) using the scrollPhase property.
3. Research AXUIElement APIs: AXUIElementCopyElementAtPosition for hit-testing, getting window role/subrole to detect title bars, and AXUIElementSetAttributeValue for setting AXPosition and AXSize on windows.
4. Research NSScreen.screens to get screen dimensions for calculating tile positions.
</setup>

<tasks>
1. Create Package.swift at the project root with:
   - Swift tools version 6.0
   - A single executable target named 'Swipey'
   - Platform: .macOS(.v14)
   - Sources in Sources/Swipey/

2. Create Sources/Swipey/main.swift that:
   - Creates an NSApplication instance
   - Creates and sets an AppDelegate
   - Runs the app with app.run()

3. Create Sources/Swipey/AppDelegate.swift with an NSApplicationDelegate that:
   - On applicationDidFinishLaunching: initializes StatusBarController, AccessibilityManager, and GestureMonitor
   - Stores references to all managers to prevent deallocation

4. Create Sources/Swipey/StatusBarController.swift that:
   - Creates an NSStatusItem with a system symbol icon (like rectangle.split.2x1)
   - Adds a menu with items: 'Accessibility: Granted/Not Granted' (disabled label), a separator, and 'Quit Swipey'
   - Updates the accessibility label dynamically when permission status changes

5. Create Sources/Swipey/AccessibilityManager.swift that:
   - Checks AXIsProcessTrusted() on init
   - If not trusted, calls AXIsProcessTrustedWithOptions with kAXTrustedCheckOptionPrompt = true to show the system prompt
   - Provides a public var isTrusted: Bool property
   - Provides a method to re-check trust status

6. Create Sources/Swipey/TilePosition.swift with:
   - An enum TilePosition with cases: maximize, leftHalf, rightHalf
   - A method frame(for screen: NSScreen) -> CGRect that calculates the target frame:
     - maximize: screen.visibleFrame inset by 12pt on each side
     - leftHalf: left 50% of visibleFrame with small gap
     - rightHalf: right 50% of visibleFrame with small gap

7. Create Sources/Swipey/TitleBarDetector.swift that:
   - Takes a CGPoint (mouse location in screen coordinates) and returns an optional AXUIElement (the window) if the cursor is over a title bar
   - Uses AXUIElementCreateSystemWide() and AXUIElementCopyElementAtPosition to get the element under the cursor
   - Walks up the element hierarchy (AXParent) to find the window element
   - Checks if the original element's subrole is AXTitleBar, AXCloseButton, AXMinimizeButton, AXZoomButton, or AXToolbarButton -- or if the element role is AXToolbar or AXTitleBar area
   - Returns the window AXUIElement if on a title bar area, nil otherwise
   - IMPORTANT: Coordinate systems differ between NSScreen (origin bottom-left) and Accessibility/CGEvent (origin top-left). Convert properly using the main screen height.

8. Create Sources/Swipey/WindowManager.swift that:
   - Has a method tile(window: AXUIElement, to position: TilePosition) that:
     - Gets the screen the window is currently on (by reading AXPosition and finding which NSScreen contains it)
     - Calculates the target frame using TilePosition.frame(for:)
     - Sets AXPosition and AXSize on the window AXUIElement
   - Handles the AX attribute setting with proper CFTypeRef bridging

9. Create Sources/Swipey/GestureStateMachine.swift that:
   - Tracks cumulative deltaX and deltaY from scroll events
   - Has a dead zone threshold (e.g. 30 points of cumulative delta before activating)
   - Once past dead zone, determines primary direction:
     - abs(deltaY) > abs(deltaX) AND deltaY < 0 (scroll up) -> .maximize
     - abs(deltaX) > abs(deltaY) AND deltaX < 0 (scroll left) -> .leftHalf
     - abs(deltaX) > abs(deltaY) AND deltaX > 0 (scroll right) -> .rightHalf
   - Has states: idle, tracking, resolved(TilePosition)
   - reset() method to go back to idle
   - feed(deltaX:deltaY:) method that updates state
   - NOTE: scrollWheel deltaX/deltaY signs -- verify which direction is positive/negative by logging during testing. Natural scrolling may invert values. The gesture direction should match the PHYSICAL finger movement direction, not the scroll content direction. If natural scrolling inverts values, invert them back so swipe-left means fingers move left.

10. Create Sources/Swipey/GestureMonitor.swift that:
    - Creates a CGEventTap for .scrollWheel events at .cghidEventTap
    - In the callback, filters for trackpad events only (check scrollPhase != 0, as mouse scroll events have scrollPhase of 0)
    - On scroll phase began: check TitleBarDetector if cursor is on title bar. If yes, store the target window AXUIElement and start tracking with GestureStateMachine.
    - On scroll phase changed: if tracking, feed deltas to GestureStateMachine
    - On scroll phase ended: if GestureStateMachine has resolved a position, call WindowManager.tile(). Reset state machine.
    - The event tap callback must be a C-function-pointer-compatible closure. Use a wrapper pattern: store a reference to the GestureMonitor instance and pass it as the userInfo pointer.
    - Add the event tap to the current run loop
    - If event tap creation fails (usually means no accessibility permission), log a warning

11. Wire everything together in AppDelegate:
    - Create AccessibilityManager first
    - Create StatusBarController and pass it the AccessibilityManager reference
    - Create WindowManager
    - Create GestureMonitor, passing it the WindowManager reference
    - Add a 1-second timer that re-checks accessibility status and updates the status bar

12. Create a .gitignore at the project root that ignores .build/, .swiftpm/, *.xcodeproj, .DS_Store, and xcuserdata/.

13. Create an Info.plist in the project root (or Sources/Swipey/) with LSUIElement = true so the app runs as an agent (no dock icon). Note: for SPM executables, the Info.plist may need to be embedded differently. If SPM does not support Info.plist embedding directly, instead set LSUIElement programmatically in AppDelegate using NSApplication.shared.setActivationPolicy(.accessory).

14. Verify the project compiles with 'swift build' from the project root. Fix any compilation errors. Common issues to watch for:
    - CGEventTap callback must be @convention(c) compatible
    - AXValue bridging for CGPoint/CGSize requires AXValueCreate/AXValueGetValue
    - Sendability warnings in Swift 6 -- use @unchecked Sendable or nonisolated where needed
    - Import ApplicationServices for Accessibility APIs, import CoreGraphics for CGEventTap
</tasks>

<testing>
1. Run 'swift build' from /Users/omarmaroki/Projects/swipey and verify it compiles with zero errors.
2. Review each source file to verify:
   - No force unwraps except where truly safe
   - Proper coordinate system conversion between CG and NS
   - Event tap callback is C-compatible
   - AXUIElement memory management is correct (these are CFTypeRef and need proper bridging)
3. Commit all files with git.
</testing>

Output <promise>COMPLETE</promise> when all tasks are done.
```

---

## Phase 2: Advanced Features

```
<background>
You are an expert macOS/Swift developer continuing work on Swipey, a lightweight menu bar window tiling app in /Users/omarmaroki/Projects/swipey. Phase 1 is complete: the app compiles, has a menu bar presence, detects trackpad gestures on title bars, and tiles windows to maximize/left-half/right-half positions.

Phase 2 adds:
- Compound gestures for quarter tiling (swipe diagonal or swipe horizontal then vertical in same gesture)
- Extended swipe up triggers native macOS fullscreen (green button)
- Swipe down restores window to its previous size/position
- Visual preview overlay showing target tile zone during swipe
- Multi-monitor support (tile to the screen the cursor is on)
- Smooth animation when tiling
</background>

<setup>
1. Read all existing source files in Sources/Swipey/ to understand current architecture and patterns.
2. Run 'swift build' to confirm the project compiles cleanly before making changes.
3. Research how to trigger native macOS fullscreen via AXUIElement -- look for AXFullScreen attribute or pressing the AXZoomButton on the window.
4. Research NSWindow with level .floating and NSVisualEffectView for creating a translucent overlay preview.
5. Research NSScreen.screens and how to determine which screen a given CGPoint falls on.
</setup>

<tasks>
1. Update TilePosition enum to add new cases:
   - topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
   - fullscreen (native macOS green-button fullscreen)
   - restore (return to previous size/position)
   - Update frame(for:) to calculate quarter frames (divide visibleFrame into quadrants with small gaps)
   - fullscreen and restore do not need frame calculations (handled specially in WindowManager)

2. Update GestureStateMachine to support compound gestures:
   - After resolving a primary horizontal direction (leftHalf/rightHalf), continue tracking vertical delta
   - If significant vertical delta accumulates after horizontal resolution:
     - Was leftHalf + swipe up -> topLeftQuarter
     - Was leftHalf + swipe down -> bottomLeftQuarter
     - Was rightHalf + swipe up -> topRightQuarter
     - Was rightHalf + swipe down -> bottomRightQuarter
   - For vertical primary direction (swipe up):
     - Small magnitude (past dead zone but under large threshold) -> maximize
     - Large magnitude (e.g. 2x the dead zone threshold) -> fullscreen
   - Swipe down -> restore
   - The state machine should update its resolved position in real-time as the gesture continues, so the preview overlay can update live

3. Update WindowManager to handle the new tile positions:
   - For fullscreen: use AXUIElement to find the windows AXZoomButton attribute and perform AXPress on it. Alternatively set AXFullScreen attribute to true.
   - For restore: before tiling any window, save its current position and size in a dictionary keyed by window (use the windows CGWindowID or AXUIElement hash). On restore, look up the saved frame and apply it. If no saved frame exists, do nothing.

4. Create Sources/Swipey/PreviewOverlay.swift:
   - A borderless, transparent NSWindow at NSWindow.Level.floating + 1
   - Contains an NSVisualEffectView with material .hudWindow and blending mode .behindWindow
   - Rounded corners (cornerRadius ~12)
   - A subtle border (1pt, white at 30% opacity)
   - Methods: show(frame: CGRect, on screen: NSScreen), update(frame: CGRect), hide()
   - Show with a quick fade-in animation (0.15s), hide with fade-out
   - The overlay window should be non-activating (styleMask includes .nonactivatingPanel or use NSPanel) and ignores mouse events (ignoresMouseEvents = true)

5. Integrate PreviewOverlay with the gesture flow:
   - When GestureStateMachine transitions from idle to tracking (past dead zone), show the overlay at the resolved positions frame
   - As the resolved position changes during the gesture (e.g. leftHalf -> topLeftQuarter), animate the overlay to the new frame
   - When gesture ends, hide the overlay and perform the tile
   - When gesture is cancelled (e.g. scroll ended before dead zone), ensure overlay is hidden

6. Add multi-monitor support:
   - In GestureMonitor, when a gesture begins, record the cursor position and determine which NSScreen it is on using NSScreen.screens and checking which screen frame contains the point
   - Pass the target screen through to WindowManager.tile() and TilePosition.frame(for:)
   - The preview overlay should appear on the correct screen
   - If the window is on a different screen than the cursor, it should still tile to the screen the cursor is on (allowing cross-monitor tiling)

7. Add smooth animation to window tiling:
   - After hiding the preview overlay, animate the window to its target position
   - Use a short NSAnimationContext or Core Animation-based approach
   - Alternatively, move the window in small incremental steps using a DispatchSource timer for a smooth slide effect (since AXUIElement does not natively support animation)
   - Keep animation short (~0.2s) so it feels snappy

8. Update StatusBarController menu:
   - Add a 'Swipey is running' label at top
   - Add an 'About' item that shows app version
   - Ensure accessibility status label updates properly

9. Edge case handling:
   - If the window is already in the target position, do nothing (avoid redundant moves)
   - If the user swipes on the Swipey overlay window itself, ignore it
   - Handle the case where a window enters native fullscreen: it moves to its own Space, so do not try to move it further
   - Debounce rapid gestures: after tiling, add a short cooldown (~0.3s) before accepting new gestures

10. Verify everything compiles with 'swift build'. Fix all errors and warnings.
</tasks>

<testing>
1. Run 'swift build' and verify zero errors.
2. Review all modified and new files for:
   - Correct coordinate system handling across screens
   - No memory leaks with AXUIElement references
   - Preview overlay properly handles show/hide lifecycle
   - Gesture state machine correctly resolves all 9 positions (maximize, fullscreen, restore, leftHalf, rightHalf, and 4 quarters)
3. Review the gesture state machine logic carefully -- draw out the state transitions mentally and verify compound gestures resolve correctly.
4. Commit all changes with git.
</testing>

Output <promise>COMPLETE</promise> when all tasks are done.
```

---

## Running the Commands

To execute each phase, use `/ralph-loop` and paste the corresponding command block above.

Phase 1 must complete before starting Phase 2.
