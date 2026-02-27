#!/usr/bin/env bash
#
# distribute.sh — Full build, sign, notarize, and package pipeline for Tokenomics.
#
# Prerequisites:
#   brew install create-dmg
#   xcrun notarytool store-credentials "tokenomics-notarize" \
#       --apple-id <your-apple-id> \
#       --team-id RPDDQP7KZ5 \
#       --password <app-specific-password>
#
# Usage:
#   ./scripts/distribute.sh
#
# Output:
#   Tokenomics-<version>.dmg in the project root.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/tokenomics-build"
ARCHIVE_PATH="$BUILD_DIR/Tokenomics.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Tokenomics.app"
EXPORT_OPTIONS="$PROJECT_ROOT/ExportOptions.plist"
SCHEME="Tokenomics"
CONFIGURATION="Release"
NOTARIZE_PROFILE="tokenomics-notarize"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() {
    echo ""
    echo "==> $1"
}

die() {
    echo "ERROR: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

step "Checking prerequisites"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found. Install with: brew install xcodegen"
command -v create-dmg >/dev/null 2>&1 || die "create-dmg not found. Install with: brew install create-dmg"

# Confirm the keychain profile exists before spending time on a full build
xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1 \
    || die "Notarytool keychain profile '$NOTARIZE_PROFILE' not found.\n\nSet it up with:\n  xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" --apple-id <email> --team-id RPDDQP7KZ5 --password <app-specific-password>"

# ---------------------------------------------------------------------------
# Step 1: Generate Xcode project
# ---------------------------------------------------------------------------

step "Generating Xcode project with XcodeGen"
cd "$PROJECT_ROOT"
xcodegen generate

# Read the version AFTER xcodegen runs — xcodegen overwrites Info.plist from
# project.yml, so reading before this step would get the previous release's value.
APP_VERSION=$(defaults read "$PROJECT_ROOT/Tokenomics/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="Tokenomics-${APP_VERSION}.dmg"
DMG_OUTPUT="$PROJECT_ROOT/$DMG_NAME"

# ---------------------------------------------------------------------------
# Step 2: Clean build directory
# ---------------------------------------------------------------------------

step "Preparing build directory at $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 3: Archive
# ---------------------------------------------------------------------------

step "Archiving (Release, Developer ID)"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="RPDDQP7KZ5" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    archive

# Verify the archive was actually created (xcpretty can swallow non-zero exits)
[[ -d "$ARCHIVE_PATH" ]] || die "Archive not found at $ARCHIVE_PATH — build likely failed. Re-run without xcpretty to see raw output."

# ---------------------------------------------------------------------------
# Step 4: Export archive
# ---------------------------------------------------------------------------

step "Exporting archive"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

[[ -d "$APP_PATH" ]] || die "Exported .app not found at $APP_PATH"

# ---------------------------------------------------------------------------
# Step 5: Notarize the .app
# ---------------------------------------------------------------------------

step "Notarizing Tokenomics.app"

# Zip the .app — notarytool requires a zip or dmg, not a bare .app
APP_ZIP="$BUILD_DIR/Tokenomics.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait

# ---------------------------------------------------------------------------
# Step 6: Staple the ticket to the .app
# ---------------------------------------------------------------------------

step "Stapling notarization ticket to Tokenomics.app"
xcrun stapler staple "$APP_PATH"

# Verify the staple succeeded
xcrun stapler validate "$APP_PATH"

# ---------------------------------------------------------------------------
# Step 7: Create DMG
# ---------------------------------------------------------------------------

step "Creating DMG: $DMG_NAME"

# Remove any existing DMG at the output path
[[ -f "$DMG_OUTPUT" ]] && rm "$DMG_OUTPUT"

# create-dmg returns exit code 2 when "disk image done" but Finder layout
# AppleScript had minor issues — this is cosmetic, not a real failure.
create-dmg \
    --volname "Tokenomics" \
    --volicon "$PROJECT_ROOT/Tokenomics/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
    --background "$PROJECT_ROOT/Tokenomics/Resources/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --text-size 14 \
    --icon "Tokenomics.app" 128 185 \
    --hide-extension "Tokenomics.app" \
    --app-drop-link 412 185 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$APP_PATH" || true

[[ -f "$DMG_OUTPUT" ]] || die "DMG not found at $DMG_OUTPUT — create-dmg may have failed"

# ---------------------------------------------------------------------------
# Step 8: Sign the DMG
# ---------------------------------------------------------------------------

step "Signing $DMG_NAME"
codesign --sign "Developer ID Application" --timestamp "$DMG_OUTPUT"

# ---------------------------------------------------------------------------
# Step 9: Notarize the DMG
# ---------------------------------------------------------------------------

step "Notarizing $DMG_NAME"
xcrun notarytool submit "$DMG_OUTPUT" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait

# ---------------------------------------------------------------------------
# Step 10: Staple the ticket to the DMG
# ---------------------------------------------------------------------------

step "Stapling notarization ticket to DMG"
xcrun stapler staple "$DMG_OUTPUT"

xcrun stapler validate "$DMG_OUTPUT"

# ---------------------------------------------------------------------------
# Step 11: Generate Sparkle appcast
# ---------------------------------------------------------------------------

step "Updating Sparkle appcast"

# Sparkle's generate_appcast tool scans a directory of DMGs and produces
# (or updates) an appcast.xml with EdDSA signatures and version info.
# The key was generated with Sparkle's generate_keys and lives in Keychain.
SPARKLE_BIN=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Tokenomics*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    -print -quit 2>/dev/null)

if [[ -n "$SPARKLE_BIN" ]]; then
    # generate_appcast expects a directory containing the DMG(s)
    APPCAST_DIR="$BUILD_DIR/appcast-staging"
    mkdir -p "$APPCAST_DIR"
    cp "$DMG_OUTPUT" "$APPCAST_DIR/"

    # If an existing appcast exists, copy it so generate_appcast can update it
    [[ -f "$PROJECT_ROOT/appcast.xml" ]] && cp "$PROJECT_ROOT/appcast.xml" "$APPCAST_DIR/"

    "$SPARKLE_BIN" "$APPCAST_DIR" \
        --download-url-prefix "https://github.com/rob-stout/Tokenomics/releases/download/v${APP_VERSION}/"

    # Copy the updated appcast back to the project root
    cp "$APPCAST_DIR/appcast.xml" "$PROJECT_ROOT/appcast.xml"
    echo "Appcast updated at $PROJECT_ROOT/appcast.xml"
else
    echo "WARNING: Sparkle generate_appcast not found — skipping appcast generation."
    echo "Build the project in Xcode first to download Sparkle, then re-run."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo "Done. Distributable DMG:"
echo "  $DMG_OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Verify with Gatekeeper:"
echo "       spctl -a -t open --context context:primary-signature -v \"$DMG_OUTPUT\""
echo "  2. Create a GitHub Release tagged v${APP_VERSION}"
echo "  3. Upload $DMG_NAME to the release"
echo "  4. Commit and push the updated appcast.xml"
