#!/bin/bash
set -euo pipefail

APP_NAME="Swipey"
BUNDLE_ID="com.swipey.app"
VERSION="1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ENTITLEMENTS="Swipey.entitlements"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ICON_SOURCE="AppIcon.icns"

# --- Detect signing identity ---
DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" \
    | head -1 \
    | sed 's/.*"\(.*\)"/\1/' || true)

if [ -n "$DEVELOPER_ID" ]; then
    echo "Using Developer ID: ${DEVELOPER_ID}"
    SIGN_IDENTITY="$DEVELOPER_ID"
    CAN_NOTARIZE=true
else
    echo "⚠ No Developer ID Application certificate found."
    echo "  Falling back to Apple Development signing (local only)."
    echo "  To distribute, create a Developer ID Application certificate at:"
    echo "  https://developer.apple.com/account/resources/certificates/list"
    SIGN_IDENTITY="Apple Development: Omar Maroki (85N386F5TF)"
    CAN_NOTARIZE=false
fi

# --- Build ---
echo ""
echo "Building ${APP_NAME}..."
swift build -c release

# --- Create .app bundle ---
echo "Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Copy app icon if it exists
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "${RESOURCES}/AppIcon.icns"
    ICON_REF="AppIcon"
    echo "App icon copied."
else
    ICON_REF=""
    echo "⚠ No ${ICON_SOURCE} found — app will use default icon."
    echo "  Place a 1024x1024 .icns file at ${ICON_SOURCE} and rebuild."
fi

# --- Info.plist ---
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Omar Maroki. All rights reserved.</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_REF}</string>
</dict>
</plist>
PLIST

# --- Code sign the .app ---
echo ""
echo "Signing ${APP_BUNDLE} with: ${SIGN_IDENTITY}..."
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "${APP_BUNDLE}"

echo "Verifying signature..."
codesign -dvvv "${APP_BUNDLE}" 2>&1 | head -15

# --- Create DMG ---
echo ""
echo "Creating ${DMG_NAME}..."
rm -f "${DMG_NAME}"

# Create a temporary directory for DMG contents
DMG_STAGING=$(mktemp -d)
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_NAME"

rm -rf "$DMG_STAGING"

# Sign the DMG
echo "Signing ${DMG_NAME}..."
codesign --force --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$DMG_NAME"

# --- Notarize ---
if [ "$CAN_NOTARIZE" = true ]; then
    echo ""
    echo "Submitting ${DMG_NAME} for notarization..."
    echo "(This may take a few minutes)"

    # Extract Team ID from the signing identity
    TEAM_ID=$(echo "$DEVELOPER_ID" | grep -oE '\([A-Z0-9]+\)$' | tr -d '()')

    xcrun notarytool submit "$DMG_NAME" \
        --keychain-profile "notarytool-profile" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_NAME"

    echo ""
    echo "Verifying notarization..."
    spctl --assess --type open --context context:primary-signature "$DMG_NAME" && echo "DMG accepted by Gatekeeper" || echo "⚠ Gatekeeper check failed"
else
    echo ""
    echo "⚠ Skipping notarization (no Developer ID certificate)."
    echo "  The DMG was created but won't pass Gatekeeper on other machines."
fi

# --- Reset accessibility for local testing ---
echo ""
echo "Resetting accessibility permission (will need re-grant)..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

# --- Done ---
echo ""
echo "Done!"
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_NAME}"
echo ""
echo "To install locally: cp -r ${APP_BUNDLE} /Applications/"
echo "To distribute: share ${DMG_NAME}"
