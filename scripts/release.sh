#!/usr/bin/env bash
#
# release.sh — One-command stable release for Tokenomics.
#
# Replaces the manual three-step deploy note:
#   1. Bumps the version in project.yml (main app + widgets targets only)
#   2. Runs ./scripts/distribute.sh   (xcodegen, build, sign, notarize, DMG, appcast)
#   3. Commits the build-number sync distribute.sh made
#   4. Runs ./scripts/publish.sh      (GitHub Release, casks, appcast push, site sync)
#
# Usage:
#   ./scripts/release.sh 2.9.1              # auto-generated release notes
#   ./scripts/release.sh 2.9.1 notes.md     # notes.md as the release body
#
# Prerequisites: everything distribute.sh and publish.sh already require
# (create-dmg, notarytool profile, gh auth, tap repo clone).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YML_PATH="$PROJECT_ROOT/project.yml"
VERSION="${1:-}"
NOTES_FILE="${2:-}"

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

[[ -n "$VERSION" ]] || die "Usage: ./scripts/release.sh <version> [notes.md]  (e.g. ./scripts/release.sh 2.9.1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Version must be X.Y.Z (stable). For betas use distribute-beta.sh."
if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
    die "Notes file not found: $NOTES_FILE"
fi

cd "$PROJECT_ROOT"

# Release commits are made below — refuse to mix them with unrelated edits.
git diff-index --quiet HEAD \
    || die "Working tree has uncommitted changes. Commit or stash them first."

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "WARNING: You are on '$BRANCH', not main."
    echo "  publish.sh pushes 'origin main' — release commits made on this branch"
    echo "  stay local until you fast-forward main yourself."
    read -r -p "  Release from '$BRANCH' anyway? [y/N] " REPLY
    [[ "$REPLY" == "y" || "$REPLY" == "Y" ]] || die "Aborted."
fi

CURRENT_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$YML_PATH" | awk -F'"' '{print $2}')
[[ -n "$CURRENT_VERSION" ]] || die "Could not read CFBundleShortVersionString from project.yml"
[[ "$VERSION" != "$CURRENT_VERSION" ]] \
    || die "project.yml is already at $VERSION — distribute.sh refuses to rebuild a shipped version."

echo "Branch:   $BRANCH"
echo "Version:  $CURRENT_VERSION → $VERSION"

# ---------------------------------------------------------------------------
# Step 1: Bump version in project.yml
# ---------------------------------------------------------------------------

step "Bumping version in project.yml"

# Scope the sed to the CURRENT app version so only the main app + widgets
# entries (which share it) are updated — the Safari/MAS targets version
# independently and must not be touched.
sed -i '' "s/CFBundleShortVersionString: \"$CURRENT_VERSION\"/CFBundleShortVersionString: \"$VERSION\"/g" "$YML_PATH"

BUMPED_COUNT=$(grep -c "CFBundleShortVersionString: \"$VERSION\"" "$YML_PATH")
[[ "$BUMPED_COUNT" -eq 2 ]] \
    || die "Expected exactly 2 bumped version entries (app + widgets), found $BUMPED_COUNT. Check project.yml manually."

git add "$YML_PATH"
git commit -m "chore: bump version to $VERSION"
echo "Committed version bump ✓"

# ---------------------------------------------------------------------------
# Step 2: Build, sign, notarize, package
# ---------------------------------------------------------------------------

step "Running distribute.sh"

"$PROJECT_ROOT/scripts/distribute.sh"

# ---------------------------------------------------------------------------
# Step 3: Commit the build-number sync distribute.sh made
# ---------------------------------------------------------------------------

step "Committing build-number sync"

BUILD=$(grep -m1 'CFBundleVersion:' "$YML_PATH" | awk -F'"' '{print $2}')
git add "$YML_PATH" "$PROJECT_ROOT/Tokenomics/Resources/Info.plist"
if git diff --cached --quiet; then
    echo "No build-number changes to commit."
else
    git commit -m "chore: v$VERSION (build $BUILD)"
    echo "Committed build $BUILD ✓"
fi

# ---------------------------------------------------------------------------
# Step 4: Publish (GitHub Release, casks, appcast, site sync)
# ---------------------------------------------------------------------------

step "Running publish.sh"

if [[ -n "$NOTES_FILE" ]]; then
    "$PROJECT_ROOT/scripts/publish.sh" "$NOTES_FILE"
else
    "$PROJECT_ROOT/scripts/publish.sh"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 5: Sync main (when releasing from another branch)
# ---------------------------------------------------------------------------

# Sparkle reads appcast.xml from main, so the release isn't live until main
# carries the release commits. Fast-forward without a checkout so concurrent
# sessions on other branches aren't disrupted.
if [[ "$BRANCH" != "main" ]]; then
    step "Fast-forwarding main to $BRANCH"
    git fetch origin main
    if git merge-base --is-ancestor origin/main "$BRANCH"; then
        git push origin "$BRANCH:main"
        # Keep the local main branch in sync too (no-op if it can't fast-forward)
        git fetch . "$BRANCH:main" 2>/dev/null \
            || echo "  (local main not fast-forwarded — it has diverged; origin/main is correct)"
        echo "main fast-forwarded to $BRANCH ✓"
    else
        echo "WARNING: main has diverged from $BRANCH — cannot fast-forward."
        echo "The release is NOT live for Sparkle until appcast.xml reaches main."
        echo "Merge manually, then push:"
        echo "  git checkout main && git merge $BRANCH && git push origin main"
    fi
fi

echo ""
echo "✅ release.sh complete — v$VERSION (build $BUILD)"
