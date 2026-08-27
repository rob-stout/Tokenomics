#!/usr/bin/env bash
#
# publish.sh — Post-release automation for Tokenomics.
#
# Run AFTER ./scripts/distribute.sh has built and notarized the DMG. This
# script handles every step that previously required manual gh + git commands:
#
#   1. Verify the DMG with Gatekeeper
#   2. Compute SHA-256
#   3. Create the GitHub Release (or upload asset to an existing one)
#   4. Update Casks/tokenomics.rb in this repo, commit, push
#   5. Update Casks/tokenomics.rb in the Homebrew tap repo, commit, push
#   6. Commit + push the auto-generated appcast.xml entry
#   7. Trigger the trytokenomics-site sync-version workflow so the website
#      fallbacks update without waiting for the daily cron
#
# Prerequisites:
#   - distribute.sh has been run successfully for the current version
#   - gh CLI authenticated (gh auth login)
#   - The Homebrew tap repo is cloned locally (default path below)
#
# Usage:
#   ./scripts/publish.sh                    # auto-generated release notes
#   ./scripts/publish.sh notes.md           # use notes.md as the release body
#
# Environment overrides:
#   TAP_REPO_PATH   path to homebrew-tap clone
#                   (default: /opt/homebrew/Library/Taps/rob-stout/homebrew-tap)
#   SITE_REPO       owner/repo for the marketing site
#                   (default: rob-stout/trytokenomics-site)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_REPO_PATH="${TAP_REPO_PATH:-/opt/homebrew/Library/Taps/rob-stout/homebrew-tap}"
SITE_REPO="${SITE_REPO:-rob-stout/trytokenomics-site}"
NOTES_FILE="${1:-}"

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
# Preflight
# ---------------------------------------------------------------------------

step "Preflight"

command -v gh >/dev/null 2>&1 || die "gh CLI not found. Install with: brew install gh"
gh auth status >/dev/null 2>&1 || die "gh CLI not authenticated. Run: gh auth login"

[[ -d "$TAP_REPO_PATH/.git" ]] || die "Tap repo not found at $TAP_REPO_PATH. Set TAP_REPO_PATH if it lives elsewhere."

# Pull version from project.yml — this is the source of truth.
APP_VERSION=$(grep 'CFBundleShortVersionString:' "$PROJECT_ROOT/project.yml" \
    | head -1 | awk -F'"' '{print $2}')
[[ -n "$APP_VERSION" ]] || die "Could not read CFBundleShortVersionString from project.yml"

DMG_NAME="Tokenomics-${APP_VERSION}.dmg"
DMG_PATH="$PROJECT_ROOT/$DMG_NAME"
TAG="v${APP_VERSION}"

[[ -f "$DMG_PATH" ]] || die "DMG not found at $DMG_PATH. Run ./scripts/distribute.sh first."

# Refuse to publish a notes file the user gave us if it doesn't exist
if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
    die "Notes file not found: $NOTES_FILE"
fi

echo "Version:  $APP_VERSION"
echo "Tag:      $TAG"
echo "DMG:      $DMG_PATH"
echo "Tap repo: $TAP_REPO_PATH"

# ---------------------------------------------------------------------------
# Step 1: Gatekeeper verify
# ---------------------------------------------------------------------------

step "Verifying Gatekeeper signature"

spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 \
    | grep -q "accepted" \
    || die "Gatekeeper rejected the DMG. Check notarization status."
echo "Gatekeeper: accepted (notarized)"

# ---------------------------------------------------------------------------
# Step 2: Compute SHA-256
# ---------------------------------------------------------------------------

step "Computing SHA-256"

DMG_SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
[[ -n "$DMG_SHA" ]] || die "Failed to compute SHA-256"
echo "SHA-256: $DMG_SHA"

# ---------------------------------------------------------------------------
# Step 3: GitHub Release
# ---------------------------------------------------------------------------

step "Creating GitHub Release $TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Uploading asset only (clobber=true)."
    gh release upload "$TAG" "$DMG_PATH" --clobber
else
    if [[ -n "$NOTES_FILE" ]]; then
        gh release create "$TAG" \
            --title "$TAG" \
            --notes-file "$NOTES_FILE" \
            "$DMG_PATH"
    else
        # Auto-generate notes from commits since the previous tag
        gh release create "$TAG" \
            --title "$TAG" \
            --generate-notes \
            "$DMG_PATH"
    fi
fi
echo "Release URL: https://github.com/rob-stout/Tokenomics/releases/tag/$TAG"

# ---------------------------------------------------------------------------
# Step 4: Update Casks/tokenomics.rb in this repo
# ---------------------------------------------------------------------------

step "Updating Casks/tokenomics.rb (app repo)"

CASK_LOCAL="$PROJECT_ROOT/Casks/tokenomics.rb"
[[ -f "$CASK_LOCAL" ]] || die "Cask file not found at $CASK_LOCAL"

# Replace `version "X.Y.Z"` and the next `sha256 "..."` line.
# Using awk to avoid sed -i portability issues with macOS BSD sed.
awk -v v="$APP_VERSION" -v s="$DMG_SHA" '
    /^[[:space:]]*version[[:space:]]+"/ { sub(/"[^"]*"/, "\"" v "\""); print; next }
    /^[[:space:]]*sha256[[:space:]]+"/  { sub(/"[^"]*"/, "\"" s "\""); print; next }
    { print }
' "$CASK_LOCAL" > "$CASK_LOCAL.tmp" && mv "$CASK_LOCAL.tmp" "$CASK_LOCAL"

# ---------------------------------------------------------------------------
# Step 5: Commit + push app repo
# ---------------------------------------------------------------------------

step "Committing + pushing app repo"

cd "$PROJECT_ROOT"
git add Casks/tokenomics.rb appcast.xml 2>/dev/null || true

# Anything to commit?
if git diff --cached --quiet; then
    echo "No app-repo changes to commit (cask + appcast already up to date)."
else
    git commit -m "chore: publish $TAG — appcast + cask sha256"
    # Push the branch we actually committed to. A hardcoded `origin main` fails
    # (or silently pushes a stale main) when releasing from another branch —
    # release.sh handles syncing main afterwards.
    git push origin HEAD
fi

# ---------------------------------------------------------------------------
# Step 6: Update + push tap repo
# ---------------------------------------------------------------------------

step "Updating tap repo"

CASK_TAP="$TAP_REPO_PATH/Casks/tokenomics.rb"
[[ -f "$CASK_TAP" ]] || die "Tap cask file not found at $CASK_TAP"

awk -v v="$APP_VERSION" -v s="$DMG_SHA" '
    /^[[:space:]]*version[[:space:]]+"/ { sub(/"[^"]*"/, "\"" v "\""); print; next }
    /^[[:space:]]*sha256[[:space:]]+"/  { sub(/"[^"]*"/, "\"" s "\""); print; next }
    { print }
' "$CASK_TAP" > "$CASK_TAP.tmp" && mv "$CASK_TAP.tmp" "$CASK_TAP"

cd "$TAP_REPO_PATH"
git add Casks/tokenomics.rb
if git diff --cached --quiet; then
    echo "No tap-repo changes to commit (already at $APP_VERSION)."
else
    git commit -m "chore: tokenomics $APP_VERSION"
    git push origin main
fi

# ---------------------------------------------------------------------------
# Step 7: Trigger site sync workflow
# ---------------------------------------------------------------------------

step "Triggering site sync-version workflow"

# Best-effort. Falls back to the daily scheduled run if the workflow file
# isn't present yet on $SITE_REPO.
if gh workflow run sync-version.yml --repo "$SITE_REPO" >/dev/null 2>&1; then
    echo "Triggered sync-version.yml on $SITE_REPO — fallbacks should refresh within ~30s."
else
    echo "Could not trigger sync-version.yml on $SITE_REPO."
    echo "(That's fine if the workflow isn't installed yet — daily cron will pick it up.)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo "✅ Released $TAG"
echo "   App repo:  https://github.com/rob-stout/Tokenomics/releases/tag/$TAG"
echo "   Brew:      brew install rob-stout/tap/tokenomics"
echo "   Sparkle:   appcast.xml updated; existing installs will see the update"
