#!/usr/bin/env bash
#
# distribute-appstore.sh — Mac App Store pipeline for "Tokenomics for Safari".
#
# This is a NEW, separate channel from distribute.sh (Developer ID DMG) —
# distribute.sh is untouched and stays exactly as-is. The two channels use
# different signing identities (Apple Distribution vs Developer ID
# Application) and different export methods, so they must never share an
# archive or an ExportOptions plist.
#
# Two-phase design:
#   VALIDATE (default, safe) — archive, run our own App-Group entitlement
#     check (the "ITMS-90286 checkpoint" — see below), and export locally
#     with method app-store-connect / destination export. No network upload.
#   UPLOAD (opt-in via --upload) — re-exports with destination upload,
#     authenticated with an App Store Connect API key. Actually publishes a
#     build to App Store Connect. Never runs unless you pass --upload.
#
# Prerequisites:
#   node extension/build.mjs --safari   (script runs this for you if stale)
#   xcodegen                            (regenerates the Xcode project)
#   An "Apple Distribution" identity for team RPDDQP7KZ5 in the keychain.
#   For --upload only: an App Store Connect API key (see the error message
#   this script prints if one isn't configured — it tells you exactly what
#   to create and where).
#
# Usage:
#   ./scripts/distribute-appstore.sh              # validate only (safe)
#   ./scripts/distribute-appstore.sh --upload      # validate, then upload
#
# Output:
#   A .pkg under $BUILD_DIR/export (validate) or a published build on App
#   Store Connect (upload).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/tokenomics-appstore-build"
ARCHIVE_PATH="$BUILD_DIR/TokenomicsSafari.xcarchive"
VALIDATE_EXPORT_PATH="$BUILD_DIR/export-validate"
UPLOAD_EXPORT_PATH="$BUILD_DIR/export-upload"
EXPORT_OPTIONS="$PROJECT_ROOT/ExportOptions-appstore.plist"
UPLOAD_EXPORT_OPTIONS="$BUILD_DIR/ExportOptions-appstore-upload.plist"
SCHEME="TokenomicsSafari"
CONFIGURATION="Release"
TEAM_ID="RPDDQP7KZ5"
APP_BUNDLE_ID="com.robstout.tokenomics.safari"
EXTENSION_BUNDLE_ID="com.robstout.tokenomics.safari.extension"
APP_GROUP_ID="group.com.robstout.tokenomics"
APP_NAME="Tokenomics for Safari"
EXTENSION_NAME="TokenomicsSafariExtension"

DO_UPLOAD=false
for arg in "$@"; do
    case "$arg" in
        --upload) DO_UPLOAD=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() {
    echo ""
    echo "==> $1"
}

die() {
    echo "" >&2
    echo "ERROR: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight 1: extension/dist-safari is built and current
# ---------------------------------------------------------------------------

step "Checking extension/dist-safari is current"

EXT_DIR="$PROJECT_ROOT/extension"
DIST_SAFARI="$EXT_DIR/dist-safari"

if [[ ! -d "$DIST_SAFARI" || ! -f "$DIST_SAFARI/manifest.json" ]]; then
    echo "  dist-safari missing — building it"
    (cd "$EXT_DIR" && node build.mjs --safari)
elif [[ -n "$(find "$EXT_DIR/src" -type f -newer "$DIST_SAFARI/manifest.json" 2>/dev/null)" ]]; then
    echo "  extension/src has changes newer than dist-safari — rebuilding"
    (cd "$EXT_DIR" && node build.mjs --safari)
else
    echo "  dist-safari is up to date"
fi

[[ -f "$DIST_SAFARI/manifest.json" ]] || die "extension/dist-safari/manifest.json still missing after build — check the build.mjs --safari output above."

# ---------------------------------------------------------------------------
# Preflight 2: xcodegen present + project current
# ---------------------------------------------------------------------------

step "Regenerating Xcode project with XcodeGen"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found. Install with: brew install xcodegen"

cd "$PROJECT_ROOT"
xcodegen generate

# ---------------------------------------------------------------------------
# Preflight 3: Apple Distribution identity present
# ---------------------------------------------------------------------------

step "Checking for an Apple Distribution signing identity"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Distribution"; then
    die "No \"Apple Distribution\" identity found in the keychain for team $TEAM_ID.

Create one in Xcode: Settings → Accounts → (your Apple ID) → Manage Certificates → + → Apple Distribution.
Or in the developer portal: https://developer.apple.com/account/resources/certificates/list"
fi

echo "  Apple Distribution identity found"

# ---------------------------------------------------------------------------
# Preflight 4: version/build
# ---------------------------------------------------------------------------

step "Reading companion version from project.yml"

YML_PATH="$PROJECT_ROOT/project.yml"

# TokenomicsSafari appears twice in project.yml — once as a scheme (near the
# top) and once as the actual target with the Info.plist properties we want.
# Scope the search to start only after the top-level `targets:` key so we
# land on the target block, not the scheme block (whose "TokenomicsSafari:"
# line matches the same pattern but has no CFBundle* keys under it).
APP_BLOCK=$(awk '
    /^targets:$/ { in_targets = 1 }
    in_targets && /^  TokenomicsSafari:$/ { flag = 1; next }
    in_targets && flag && /^  [A-Za-z]/ { exit }
    flag
' "$YML_PATH")
# `grep -m1 ... || true` — under `set -o pipefail`, a no-match grep (exit 1)
# would otherwise abort the whole script right here with no message (bash
# exits on the pipeline's failure before the explicit -n check below ever
# runs). Missing values are still caught by that check, with an actionable
# die().
APP_VERSION=$(grep -m1 'CFBundleShortVersionString:' <<<"$APP_BLOCK" | awk '{print $2}' | tr -d '"' || true)
APP_BUILD=$(grep -m1 'CFBundleVersion:' <<<"$APP_BLOCK" | awk '{print $2}' | tr -d '"' || true)

[[ -n "$APP_VERSION" && -n "$APP_BUILD" ]] || die "Could not read TokenomicsSafari's version/build from project.yml"

echo "  Tokenomics for Safari: $APP_VERSION (build $APP_BUILD)"
echo ""
echo "  Note: App Store exports default to manageAppVersionAndBuildNumber=YES,"
echo "  so Xcode will bump the build number on upload if $APP_BUILD was already used."
echo "  There's no appcast-style ledger for this channel (unlike distribute.sh) —"
echo "  App Store Connect is the source of truth for what's already been uploaded."

# ---------------------------------------------------------------------------
# Step 1: Clean build directory
# ---------------------------------------------------------------------------

step "Preparing build directory at $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 2: Archive
# ---------------------------------------------------------------------------

step "Archiving $SCHEME ($CONFIGURATION, Apple Distribution)"

# -allowProvisioningUpdates is required because the release config for
# TokenomicsSafari/TokenomicsSafariExtension uses Automatic signing (see the
# comments in project.yml for why Manual-without-a-profile was tried first and
# empirically fails archiving outright — no App Store profile exists yet for
# either bundle id). Automatic signing lets xcodebuild reuse whatever locally
# cached profile/identity combination is valid for team $TEAM_ID; if none
# exists AND no account/API key is available to fetch one, this step itself
# can fail with "No profiles found" — same underlying gate as the export step
# below, just hit earlier if there's nothing at all to reuse locally.
set +e
ARCHIVE_LOG="$BUILD_DIR/archive.log"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive 2>&1 | tee "$ARCHIVE_LOG"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$ARCHIVE_STATUS" -ne 0 || ! -d "$ARCHIVE_PATH" ]]; then
    die "Archive failed — see $ARCHIVE_LOG for details.

If the log mentions \"No profiles for 'com.robstout.tokenomics.safari...' were found\" or \"No Accounts\", this is the provisioning gate — see the ASC checklist further down (run this script again after completing it; the export step below prints the same checklist)."
fi

echo "  Archive succeeded: $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# Step 2.5: Verify the extension bundle actually contains the web extension
# ---------------------------------------------------------------------------

step "Verifying embedded TokenomicsSafariExtension"

BUILT_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
BUILT_APPEX="$BUILT_APP/Contents/PlugIns/$EXTENSION_NAME.appex"

[[ -d "$BUILT_APP" ]] || die "Archived app not found at $BUILT_APP"
[[ -d "$BUILT_APPEX" ]] || die "Archived appex not found at $BUILT_APPEX"

# The extension/dist-safari resources are marked `optional: true` in
# project.yml so xcodegen doesn't hard-fail before dist-safari is built — but
# that means a stale/missing dist-safari silently produces an EMPTY appex
# instead of a build error. Catch that here, the same role Step 4.5 in
# distribute.sh plays for TokenomicsBridge.
[[ -f "$BUILT_APPEX/Contents/Resources/manifest.json" ]] \
    || die "TokenomicsSafariExtension.appex has no manifest.json — the Safari extension bundle wasn't embedded. Re-run 'node extension/build.mjs --safari' and re-run this script."

echo "  TokenomicsSafariExtension contains the built web extension resources"

# ---------------------------------------------------------------------------
# Step 3: Our own "ITMS-90286 checkpoint" — App Group entitlement parity
# ---------------------------------------------------------------------------
#
# ITMS-90286 (and its siblings) is Apple's validation error for an app +
# extension whose App Group entitlements don't line up — e.g. one side using
# a team-ID-prefixed group ("<TEAM>.group.…", historically required for some
# Mac App Store capabilities) while the other uses the bare id, or one side
# missing the capability entirely. This IS the "Known wrinkle" the Safari
# plan's Phase 0 #2 flagged as the single biggest technical risk (sharing the
# App Group container across the sandbox boundary with the Developer-ID app).
# We can check this locally, for free, without any App Store Connect
# credentials — so we always do, right after archiving.

step "Checking App Group entitlement parity (app vs. extension)"

app_groups() {
    # `--entitlements :-` (colon-dash) is required to get a real plist on
    # stdout — plain `-` prints codesign's human-readable "[Dict]... [Key]..."
    # dump instead, which plutil can't parse. And plutil's keypath syntax
    # treats "." as a nesting separator, so the literal dots in
    # "com.apple.security.application-groups" must be backslash-escaped or
    # plutil looks for a nested com → apple → security → application-groups
    # structure that doesn't exist and reports "no value at that key path".
    codesign -d --entitlements :- "$1" 2>/dev/null \
        | plutil -extract 'com\.apple\.security\.application-groups' json -o - - 2>/dev/null \
        || echo "[]"
}

APP_GROUPS_JSON=$(app_groups "$BUILT_APP")
EXT_GROUPS_JSON=$(app_groups "$BUILT_APPEX")

[[ "$APP_GROUPS_JSON" != "[]" ]] || die "Tokenomics for Safari.app has no com.apple.security.application-groups entitlement — check TokenomicsSafari/TokenomicsSafari.entitlements and project.yml."
[[ "$EXT_GROUPS_JSON" != "[]" ]] || die "TokenomicsSafariExtension.appex has no com.apple.security.application-groups entitlement — check TokenomicsSafariExtension/TokenomicsSafariExtension.entitlements and project.yml."

if [[ "$APP_GROUPS_JSON" != "$EXT_GROUPS_JSON" ]]; then
    die "App Group entitlement MISMATCH between app and extension — this is exactly what ITMS-90286-style validation rejects.
  App:       $APP_GROUPS_JSON
  Extension: $EXT_GROUPS_JSON
Both must declare the identical group id. Check project.yml's application-groups entries for TokenomicsSafari and TokenomicsSafariExtension."
fi

if ! grep -q "$APP_GROUP_ID" <<<"$APP_GROUPS_JSON"; then
    die "App Group entitlement is present but doesn't contain the expected id ($APP_GROUP_ID): $APP_GROUPS_JSON"
fi

echo "  App Group entitlements match on both sides: $APP_GROUPS_JSON"

# ---------------------------------------------------------------------------
# Step 4: VALIDATE — export locally (method app-store-connect, destination export)
# ---------------------------------------------------------------------------

step "Validating (export archive, no upload)"

[[ -f "$EXPORT_OPTIONS" ]] || die "Missing $EXPORT_OPTIONS"

set +e
EXPORT_LOG="$BUILD_DIR/export-validate.log"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$VALIDATE_EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates 2>&1 | tee "$EXPORT_LOG"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$EXPORT_STATUS" -ne 0 ]]; then
    if grep -qE "No Accounts|No profiles for|requires a provisioning profile" "$EXPORT_LOG"; then
        die "Export failed at the App Store Connect provisioning boundary — expected until this is set up. Do the following in order:

  1. App ID registration (developer.apple.com/account/resources/identifiers/list):
       - Register an App ID for $APP_BUNDLE_ID
       - Register an App ID for $EXTENSION_BUNDLE_ID
       - Enable the \"App Groups\" capability on BOTH, and add them to the
         SAME group as the existing app ($APP_GROUP_ID — the group the
         Developer-ID Tokenomics app + TokenomicsWidgets already use).

  2. App Store Connect API key (appstoreconnect.apple.com → Users and Access
     → Integrations → App Store Connect API):
       - Generate a key with at least the \"Developer\" role (\"App Manager\"
         if you also want it to manage the app record).
       - Download the .p8 (Apple only lets you download it once).
       - Note the Key ID and Issuer ID shown on that page.
       - This lets xcodebuild sign in headlessly via -allowProvisioningUpdates
         (see -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID
         in 'xcodebuild -help') instead of an interactive Xcode Accounts sign-in.

  3. App Store provisioning profiles for both bundle ids — with the API key
     from step 2 in place, re-running this script should let xcodebuild create
     these automatically (that's what -allowProvisioningUpdates is for). If
     you'd rather create them by hand: developer.apple.com/account/resources/profiles/list.

  4. App Store Connect app record (appstoreconnect.apple.com → My Apps → +
     → New App) — bundle id $APP_BUNDLE_ID, name \"Tokenomics for Safari\" (or
     your preferred store name). Required before the UPLOAD step (--upload)
     will be accepted, even once export succeeds.

See $EXPORT_LOG for the exact xcodebuild error."
    fi
    die "Export failed for a reason other than the provisioning boundary — see $EXPORT_LOG"
fi

PKG_PATH=$(find "$VALIDATE_EXPORT_PATH" -maxdepth 1 -name "*.pkg" -print -quit)
[[ -n "$PKG_PATH" ]] || die "Export reported success but no .pkg found in $VALIDATE_EXPORT_PATH"

echo "  Validated. Package: $PKG_PATH"

# ---------------------------------------------------------------------------
# Step 5: UPLOAD (opt-in) — re-export with destination upload
# ---------------------------------------------------------------------------

if [[ "$DO_UPLOAD" != true ]]; then
    echo ""
    echo "Done — validated only. Re-run with --upload to publish this build to App Store Connect."
    echo "  Package: $PKG_PATH"
    exit 0
fi

step "Uploading to App Store Connect"

: "${ASC_API_KEY_PATH:=}"
: "${ASC_API_KEY_ID:=}"
: "${ASC_API_KEY_ISSUER_ID:=}"

if [[ -z "$ASC_API_KEY_PATH" || -z "$ASC_API_KEY_ID" || -z "$ASC_API_KEY_ISSUER_ID" ]]; then
    die "Upload requires an App Store Connect API key. Set these environment variables and re-run with --upload:
  ASC_API_KEY_PATH        path to the downloaded AuthKey_<KEY_ID>.p8
  ASC_API_KEY_ID           the Key ID shown next to it in App Store Connect
  ASC_API_KEY_ISSUER_ID    your team's Issuer ID (same page)

Generate one at: appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API
(See the checklist printed earlier by the VALIDATE step for the other App Store Connect setup this also requires.)"
fi

[[ -f "$ASC_API_KEY_PATH" ]] || die "ASC_API_KEY_PATH does not point to a file: $ASC_API_KEY_PATH"

# Copy the validated ExportOptions and patch destination to "upload" — never
# mutate the committed ExportOptions-appstore.plist, whose default (export)
# guarantees running it by hand can't accidentally publish a build.
cp "$EXPORT_OPTIONS" "$UPLOAD_EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Set :destination upload" "$UPLOAD_EXPORT_OPTIONS"

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$UPLOAD_EXPORT_PATH" \
    -exportOptionsPlist "$UPLOAD_EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_API_KEY_PATH" \
    -authenticationKeyID "$ASC_API_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_API_KEY_ISSUER_ID"

echo ""
echo "Done. Build $APP_VERSION ($APP_BUILD) uploaded to App Store Connect."
echo "Next: appstoreconnect.apple.com → My Apps → Tokenomics for Safari → TestFlight/App Store, to submit it for review."
