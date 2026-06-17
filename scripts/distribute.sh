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
# Step 0: Version sync — read version from project.yml, auto-increment build
# ---------------------------------------------------------------------------

step "Version sync"

PLIST_PATH="$PROJECT_ROOT/Tokenomics/Resources/Info.plist"
YML_PATH="$PROJECT_ROOT/project.yml"
APPCAST_PATH="$PROJECT_ROOT/appcast.xml"

# Version comes from project.yml (set during development, committed before running this script)
NEW_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$YML_PATH" | awk '{print $2}' | tr -d '"')
[[ -n "$NEW_VERSION" ]] || die "Could not read CFBundleShortVersionString from project.yml"

# Pull last shipped version and highest build from appcast.xml
HIGHEST_BUILD=0
SHIPPED_VERSION=""
if [[ -f "$APPCAST_PATH" ]]; then
    while IFS= read -r build; do
        build_num=${build//[^0-9]/}
        if [[ -n "$build_num" && "$build_num" -gt "$HIGHEST_BUILD" ]]; then
            HIGHEST_BUILD=$build_num
            # Grab the version string for this build
            SHIPPED_VERSION=$(grep -A1 "<sparkle:version>${build_num}</sparkle:version>" "$APPCAST_PATH" \
                | grep "shortVersionString" | sed 's/.*>\(.*\)<.*/\1/')
            # If version is on the line before, try that too
            if [[ -z "$SHIPPED_VERSION" ]]; then
                SHIPPED_VERSION=$(grep -B1 "<sparkle:version>${build_num}</sparkle:version>" "$APPCAST_PATH" \
                    | grep "shortVersionString" | sed 's/.*>\(.*\)<.*/\1/')
            fi
        fi
    done < <(grep '<sparkle:version>' "$APPCAST_PATH" | sed 's/.*<sparkle:version>\(.*\)<\/sparkle:version>.*/\1/')
fi
NEXT_BUILD=$((HIGHEST_BUILD + 1))

echo "  Last shipped: ${SHIPPED_VERSION:-none} (build ${HIGHEST_BUILD})"
echo "  Building:     $NEW_VERSION (build $NEXT_BUILD)"

# Validate new version is different from last shipped
if [[ -n "$SHIPPED_VERSION" && "$NEW_VERSION" == "$SHIPPED_VERSION" ]]; then
    die "Version $NEW_VERSION is the same as the last shipped release.\nBump the version in project.yml before distributing."
fi

# Update build number, sync version to Info.plist.
# /g: bump CFBundleVersion for BOTH targets (main app + widgets) so their
# build numbers stay in sync — without it, only the first (main) target bumps.
sed -i '' "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$NEXT_BUILD\"/g" "$YML_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST_PATH"

echo "  project.yml + Info.plist synced ✓"

# ---------------------------------------------------------------------------
# Step 1: Generate Xcode project
# ---------------------------------------------------------------------------

step "Generating Xcode project with XcodeGen"
cd "$PROJECT_ROOT"
xcodegen generate

# Version was already set in Step 0 — xcodegen regenerates Info.plist from project.yml
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
# Step 4.5: Verify embedded TokenomicsBridge binary
# ---------------------------------------------------------------------------

step "Verifying embedded TokenomicsBridge"

BRIDGE_PATH="${APP_PATH}/Contents/Helpers/TokenomicsBridge"

if [ ! -x "$BRIDGE_PATH" ]; then
    die "TokenomicsBridge binary missing or not executable at $BRIDGE_PATH"
fi

codesign -dvvv "$BRIDGE_PATH" 2>&1 | grep -q "flags=.*runtime" \
    || die "TokenomicsBridge missing hardened runtime — fix project.yml TokenomicsBridge target"

codesign -d --entitlements - "$BRIDGE_PATH" 2>&1 | grep -q "group.com.robstout.tokenomics" \
    || die "TokenomicsBridge missing App Group entitlement — fix TokenomicsBridge.entitlements"

echo "  TokenomicsBridge verification passed"

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

# Build a proper .icns volume icon from the built app's AppIcon. Feeding
# create-dmg a bundled .icns (vs. a raw PNG) gives the mounted DMG volume a
# correctly-scaled multi-resolution icon in Finder.
#
# Known cosmetic issue: the .app icon shown inside the DMG installer window
# will still look flat because the source PNGs in AppIcon.appiconset are flat
# squares — macOS does NOT auto-apply a squircle to "mac" idiom assets. To
# fix that, regenerate AppIcon.appiconset from a source that bakes in the
# macOS squircle + shadow (e.g. Bakery, iconutil + masked source PNGs, or
# Apple's Icon Composer).
VOLICON_ICNS="$BUILD_DIR/VolumeIcon.icns"
BUILT_ICNS="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -f "$BUILT_ICNS" ]]; then
    cp "$BUILT_ICNS" "$VOLICON_ICNS"
else
    # Fallback: synthesize an .icns from the appiconset PNGs.
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

# Background DPI fix. Finder computes display points as `pixels * 72 / dpi`.
# Our 1080×760 source PNG is at 72 dpi, so Finder would render it at
# 1080×760 *points* — twice the window's 540pt width. Stamping it to 144 dpi
# makes Finder render the same pixel data at 540×380 points (retina-sharp).
SRC_BG="$PROJECT_ROOT/Tokenomics/Resources/App Installer/dmg-background.png"
BG_144DPI="$BUILD_DIR/dmg-background-144dpi.png"
sips -s dpiHeight 144 -s dpiWidth 144 "$SRC_BG" --out "$BG_144DPI" >/dev/null

# create-dmg returns exit code 2 when "disk image done" but Finder layout
# AppleScript had minor issues — this is cosmetic, not a real failure.
#
# Coordinate system notes (per create-dmg issue #20 + AppleScript template):
# - `--icon X Y` is the icon's CENTER (not top-left), in points (1x).
# - `--window-size W H` is the OUTER window bounds; the title bar (~28pt)
#   eats into the content area where the background image is drawn.
# - The background renders anchored to the content-area top-left at 1:1
#   (after the DPI fix above), so icon positions align with the design.
# - The bottom ~28pt is consumed by chrome — window height bumped to 408 to
#   give the 380pt design region full visibility.
#
# Figma → create-dmg conversion (1080×760 design ÷ 2 → 540×380 points):
#   Tokenomics:    Figma TL (173, 273) size 192×192 → center (134, 184) pt
#   Apps folder:   Figma TL (698, 270) size 238×198 → center (408, 184) pt
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
