#!/usr/bin/env bash
#
# distribute-beta.sh — Build a notarized DMG for a *pre-release* (beta) build.
#
# Difference from distribute.sh:
#   - DOES NOT regenerate appcast.xml (so existing Sparkle clients on the
#     stable channel never see this build).
#   - DOES NOT touch publish.sh — caller manually creates a GitHub Release
#     marked --prerelease.
#
# Set the version in project.yml to a pre-release string before running
# (e.g. "2.9.0-beta.1"). Build number auto-increments off appcast.xml.
#
# Usage:
#   ./scripts/distribute-beta.sh
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

xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1 \
    || die "Notarytool keychain profile '$NOTARIZE_PROFILE' not found.\n\nSet it up with:\n  xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" --apple-id <email> --team-id RPDDQP7KZ5 --password <app-specific-password>"

# ---------------------------------------------------------------------------
# Step 0: Version sync — read version from project.yml, auto-increment build
# ---------------------------------------------------------------------------

step "Version sync"

PLIST_PATH="$PROJECT_ROOT/Tokenomics/Resources/Info.plist"
YML_PATH="$PROJECT_ROOT/project.yml"
APPCAST_PATH="$PROJECT_ROOT/appcast.xml"

NEW_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$YML_PATH" | awk '{print $2}' | tr -d '"')
[[ -n "$NEW_VERSION" ]] || die "Could not read CFBundleShortVersionString from project.yml"

# Sanity-check this looks like a pre-release version. We don't want anyone
# accidentally running this script on a stable version.
if [[ "$NEW_VERSION" != *-* ]]; then
    die "distribute-beta.sh expects a pre-release version (e.g. 2.9.0-beta.1) but project.yml has '$NEW_VERSION'.\nUse distribute.sh for stable releases."
fi

# Compute next build number from appcast (so build numbers stay monotonic
# even though the beta isn't published to the appcast).
HIGHEST_BUILD=0
if [[ -f "$APPCAST_PATH" ]]; then
    while IFS= read -r build; do
        build_num=${build//[^0-9]/}
        if [[ -n "$build_num" && "$build_num" -gt "$HIGHEST_BUILD" ]]; then
            HIGHEST_BUILD=$build_num
        fi
    done < <(grep '<sparkle:version>' "$APPCAST_PATH" | sed 's/.*<sparkle:version>\(.*\)<\/sparkle:version>.*/\1/')
fi

# Also check the in-file build, in case a previous beta on this machine
# already bumped past the appcast.
INFILE_BUILD=$(grep -m1 'CFBundleVersion:' "$YML_PATH" | awk '{print $2}' | tr -d '"')
if [[ -n "$INFILE_BUILD" && "$INFILE_BUILD" -gt "$HIGHEST_BUILD" ]]; then
    HIGHEST_BUILD=$INFILE_BUILD
fi

NEXT_BUILD=$((HIGHEST_BUILD + 1))

echo "  Highest known build: $HIGHEST_BUILD"
echo "  Building:            $NEW_VERSION (build $NEXT_BUILD)"

sed -i '' "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$NEXT_BUILD\"/" "$YML_PATH"
sed -i '' "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$NEW_VERSION\"/g" "$YML_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST_PATH"

echo "  project.yml + Info.plist synced ✓"

# ---------------------------------------------------------------------------
# Step 1: Generate Xcode project
# ---------------------------------------------------------------------------

step "Generating Xcode project with XcodeGen"
cd "$PROJECT_ROOT"
xcodegen generate

APP_VERSION="$NEW_VERSION"
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

[[ -d "$ARCHIVE_PATH" ]] || die "Archive not found at $ARCHIVE_PATH — build likely failed."

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
xcrun stapler validate "$APP_PATH"

# ---------------------------------------------------------------------------
# Step 7: Create DMG
# ---------------------------------------------------------------------------

step "Creating DMG: $DMG_NAME"

[[ -f "$DMG_OUTPUT" ]] && rm "$DMG_OUTPUT"

VOLICON_ICNS="$BUILD_DIR/VolumeIcon.icns"
BUILT_ICNS="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -f "$BUILT_ICNS" ]]; then
    cp "$BUILT_ICNS" "$VOLICON_ICNS"
else
    ICONSET_TMP="$BUILD_DIR/VolumeIcon.iconset"
    rm -rf "$ICONSET_TMP"
    mkdir -p "$ICONSET_TMP"
    APPICONSET="$PROJECT_ROOT/Tokenomics/Resources/Assets.xcassets/AppIcon.appiconset"
    cp "$APPICONSET/icon_16x16.png"       "$ICONSET_TMP/icon_16x16.png"
    cp "$APPICONSET/icon_16x16@2x.png"    "$ICONSET_TMP/icon_16x16@2x.png"
    cp "$APPICONSET/icon_32x32.png"       "$ICONSET_TMP/icon_32x32.png"
    cp "$APPICONSET/icon_32x32@2x.png"    "$ICONSET_TMP/icon_32x32@2x.png"
    cp "$APPICONSET/icon_128x128.png"     "$ICONSET_TMP/icon_128x128.png"
    cp "$APPICONSET/icon_128x128@2x.png"  "$ICONSET_TMP/icon_128x128@2x.png"
    cp "$APPICONSET/icon_256x256.png"     "$ICONSET_TMP/icon_256x256.png"
    cp "$APPICONSET/icon_256x256@2x.png"  "$ICONSET_TMP/icon_256x256@2x.png"
    cp "$APPICONSET/icon_512x512.png"     "$ICONSET_TMP/icon_512x512.png"
    cp "$APPICONSET/icon_512x512@2x.png"  "$ICONSET_TMP/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_TMP" -o "$VOLICON_ICNS"
fi

SRC_BG="$PROJECT_ROOT/Tokenomics/Resources/App Installer/dmg-background.png"
BG_144DPI="$BUILD_DIR/dmg-background-144dpi.png"
sips -s dpiHeight 144 -s dpiWidth 144 "$SRC_BG" --out "$BG_144DPI" >/dev/null

create-dmg \
    --volname "Tokenomics" \
    --volicon "$VOLICON_ICNS" \
    --background "$BG_144DPI" \
    --window-pos 200 120 \
    --window-size 540 408 \
    --icon-size 96 \
    --text-size 14 \
    --icon "Tokenomics.app" 134 184 \
    --hide-extension "Tokenomics.app" \
    --app-drop-link 408 184 \
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
# Step 11: (intentionally skipped) — no appcast.xml regeneration for betas
# ---------------------------------------------------------------------------

echo ""
echo "Done. Pre-release DMG (NOT in appcast.xml — Sparkle clients on stable will not see it):"
echo "  $DMG_OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Verify with Gatekeeper:"
echo "       spctl -a -t open --context context:primary-signature -v \"$DMG_OUTPUT\""
echo "  2. Create a GitHub pre-release:"
echo "       gh release create v${APP_VERSION} \\"
echo "           --prerelease \\"
echo "           --target feat/zero-terminal-onboarding \\"
echo "           --title \"v${APP_VERSION} (beta)\" \\"
echo "           --notes \"Beta build — manual install only.\" \\"
echo "           \"$DMG_OUTPUT\""
echo "  3. Drag-replace /Applications/Tokenomics.app with the DMG contents to test."
