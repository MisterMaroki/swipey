# Auto-Updates via Sparkle 2 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automatic update checking and installation to Swipey using Sparkle 2, with appcast hosted on the existing static site.

**Architecture:** Sparkle 2.8.1 via SPM binary target. `UpdateController` wraps `SPUStandardUpdaterController`. Build script copies the framework into the app bundle, signs it, and generates the appcast. See `docs/plans/2026-02-19-auto-updates-design.md` for full design.

**Tech Stack:** Swift 6, SPM, Sparkle 2.8.1 (XCFramework binary target), EdDSA signing

---

### Task 1: Add Sparkle dependency to Package.swift

**Files:**
- Modify: `Package.swift`

**Step 1: Update Package.swift**

Add the Sparkle dependency, add it to `SwipeyLib` target, and add the rpath linker flag to the executable target:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Swipey",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1")
    ],
    targets: [
        .target(
            name: "SwipeyLib",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Swipey",
            exclude: ["main.swift", "Info.plist"],
            swiftSettings: [
                .define("SWIPEY_LIB")
            ]
        ),
        .executableTarget(
            name: "Swipey",
            dependencies: ["SwipeyLib"],
            path: "Sources/SwipeyApp",
            linkerSettings: [
                .unsafeFlags(["-Wl,-rpath,@loader_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "SwipeyTests",
            dependencies: ["SwipeyLib"],
            path: "Tests/SwipeyTests"
        )
    ]
)
```

**Step 2: Resolve dependencies**

Run: `swift package resolve`
Expected: Sparkle 2.8.1 downloaded, no errors.

**Step 3: Verify it builds**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (warnings OK, no errors).

**Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle 2 dependency via SPM"
```

---

### Task 2: Create UpdateController

**Files:**
- Create: `Sources/Swipey/UpdateController.swift`

**Step 1: Create UpdateController.swift**

```swift
import AppKit
import Sparkle

@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

Note: `SPUStandardUpdaterController` is `@objc` and not `Sendable`. Storing it inside a `@MainActor`-isolated class is safe because we only access it from the main actor. If the compiler complains about Sendable conformance of `SPUStandardUpdaterController`, add `@preconcurrency import Sparkle` instead of `import Sparkle`.

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/Swipey/UpdateController.swift
git commit -m "feat: add UpdateController wrapping Sparkle updater"
```

---

### Task 3: Wire UpdateController into AppDelegate

**Files:**
- Modify: `Sources/Swipey/AppDelegate.swift`

**Step 1: Add updateController property**

Add after the `settingsWindow` property declaration (line 23):

```swift
private var updateController: UpdateController!
```

**Step 2: Initialize in applicationDidFinishLaunching**

Add right after `NSApplication.shared.setActivationPolicy(.accessory)` (after line 26):

```swift
updateController = UpdateController()
```

**Step 3: Pass to StatusBarController**

Change the `statusBarController` initialization from:

```swift
statusBarController = StatusBarController(accessibilityManager: accessibilityManager)
```

to:

```swift
statusBarController = StatusBarController(accessibilityManager: accessibilityManager, updateController: updateController)
```

**Step 4: Verify it compiles (will fail — StatusBarController not updated yet)**

This is expected to fail. Move to Task 4.

---

### Task 4: Add "Check for Updates" menu item to StatusBarController

**Files:**
- Modify: `Sources/Swipey/StatusBarController.swift`

**Step 1: Update init to accept UpdateController**

Change the stored properties and init signature. Add a property:

```swift
private let updateController: UpdateController
```

Change init signature from:

```swift
init(accessibilityManager: AccessibilityManager) {
```

to:

```swift
init(accessibilityManager: AccessibilityManager, updateController: UpdateController) {
```

Add assignment at the top of init body (before the `statusItem` setup):

```swift
self.updateController = updateController
```

**Step 2: Add the menu item**

Insert the "Check for Updates..." menu item after the "Settings" item and before the separator + Quit. Find the block with `tutorialItem` and the separator before quit. After the tutorial item, add:

```swift
// Check for Updates
let updateItem = NSMenuItem(title: "Check for Updates\u{2026}", action: #selector(checkForUpdates), keyEquivalent: "")
updateItem.target = self
menu.addItem(updateItem)
```

**Step 3: Add the action method**

Add alongside the other `@objc` methods:

```swift
@objc private func checkForUpdates() {
    updateController.checkForUpdates()
}
```

**Step 4: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 5: Commit**

```bash
git add Sources/Swipey/AppDelegate.swift Sources/Swipey/StatusBarController.swift Sources/Swipey/UpdateController.swift
git commit -m "feat: wire Sparkle auto-updates into app lifecycle"
```

---

### Task 5: Update build-app.sh — Sparkle framework embedding

**Files:**
- Modify: `build-app.sh`

**Step 1: Add SUFeedURL and SUPublicEDKey to Info.plist**

In the Info.plist heredoc (around line 118-148), add these keys inside the `<dict>` block, before the closing `</dict>`:

```xml
    <key>SUFeedURL</key>
    <string>https://swipey.1273.co.uk/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_ED_KEY}</string>
```

At the top of the script (after the `BUILD_DIR` variable), add:

```bash
SPARKLE_ED_KEY="${SPARKLE_ED_KEY:-REPLACE_ME_WITH_ED25519_PUBLIC_KEY}"
```

This reads the key from an environment variable, with a placeholder default. The user will set `SPARKLE_ED_KEY` in their shell profile or pass it when running the script.

**Step 2: Copy Sparkle.framework into the app bundle**

After the `cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"` line (line 104), add:

```bash
# --- Embed Sparkle.framework ---
SPARKLE_FRAMEWORK=$(find .build/artifacts -name "Sparkle.framework" -path "*/macos-arm64_x86_64/*" | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "ERROR: Sparkle.framework not found in .build/artifacts"
    echo "  Run 'swift package resolve' first."
    exit 1
fi
FRAMEWORKS_DIR="${CONTENTS}/Frameworks"
mkdir -p "${FRAMEWORKS_DIR}"
cp -R "$SPARKLE_FRAMEWORK" "${FRAMEWORKS_DIR}/"
echo "Sparkle.framework embedded."
```

**Step 3: Sign Sparkle.framework before the app signing step**

Before the existing `codesign` of the app bundle (the line `codesign --force --sign "$SIGN_IDENTITY"` around line 154), add:

```bash
# Sign embedded Sparkle framework
echo "Signing Sparkle.framework..."
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "${FRAMEWORKS_DIR}/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "${FRAMEWORKS_DIR}/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "${FRAMEWORKS_DIR}/Sparkle.framework/Versions/B/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "${FRAMEWORKS_DIR}/Sparkle.framework"
```

**Step 4: Add generate_appcast step**

After the DMG is signed and notarized (near the end, before the `site/` copy section), add:

```bash
# --- Generate/update appcast ---
GENERATE_APPCAST=$(find .build/artifacts -name "generate_appcast" -type f | head -1)
if [ -n "$GENERATE_APPCAST" ]; then
    echo "Generating appcast..."
    "$GENERATE_APPCAST" site/
    echo "Appcast updated at site/appcast.xml"
else
    echo "WARNING: generate_appcast not found in .build/artifacts"
    echo "  Appcast will need to be generated manually."
fi
```

Note: Sparkle's SPM package includes the `generate_appcast` and `generate_keys` binaries in the artifacts. If they aren't in the SPM artifacts, the user can download them from the Sparkle GitHub release tarball (`Sparkle-2.8.1.tar.xz`) and place them in a `bin/` directory.

**Step 5: Verify the script is syntactically valid**

Run: `bash -n build-app.sh`
Expected: No output (no syntax errors).

**Step 6: Commit**

```bash
git add build-app.sh
git commit -m "build: embed Sparkle.framework and generate appcast in build script"
```

---

### Task 6: Run tests and verify build

**Step 1: Run existing tests**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass.

**Step 2: Verify release build**

Run: `swift build -c release 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Verify Sparkle artifacts exist**

Run: `find .build/artifacts -name "Sparkle.framework" | head -1`
Expected: Path to Sparkle.framework is printed.

**Step 4: Commit any fixes if needed**

---

### Task 7: Document one-time setup steps

**Files:**
- Modify: `docs/plans/2026-02-19-auto-updates-design.md` (append setup instructions)

**Step 1: Add setup section to design doc**

Append to the design doc:

```markdown

## One-Time Setup Instructions

### 1. Generate EdDSA signing keys

Find the `generate_keys` tool in Sparkle's artifacts:

```bash
GENERATE_KEYS=$(find .build/artifacts -name "generate_keys" -type f | head -1)
"$GENERATE_KEYS"
```

This creates a private key in your Keychain and prints the public key. Copy the public key.

### 2. Set the public key

Either:
- Export as env var: `export SPARKLE_ED_KEY="your-base64-public-key"`
- Or replace the placeholder in `build-app.sh` directly

### 3. First release with Sparkle

Run `./build-app.sh` as normal. The script will:
1. Embed Sparkle.framework in the app bundle
2. Add SUFeedURL and SUPublicEDKey to Info.plist
3. After creating the DMG, generate `site/appcast.xml`

### 4. Deploy

Upload the updated `site/` directory (including `appcast.xml` and the new DMG) to your static site host.
```

**Step 2: Commit**

```bash
git add docs/plans/2026-02-19-auto-updates-design.md
git commit -m "docs: add one-time Sparkle setup instructions"
```
