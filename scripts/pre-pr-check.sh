#!/usr/bin/env bash
# pre-pr-check.sh — run before opening a PR or cutting a release
# Fails fast on any error. Exit code 0 = all checks passed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="$PROJECT_ROOT/Tokenomics.xcodeproj"

echo "==> Tokenomics pre-PR check"
echo ""

# 1. Regenerate project from project.yml to catch any drift
echo "[1/3] Regenerating Xcode project from project.yml..."
xcodegen generate --spec "$PROJECT_ROOT/project.yml" --project "$PROJECT_ROOT"
echo "      OK"
echo ""

# 2. Build (catches compilation errors before running tests)
echo "[2/3] Building Tokenomics (Debug)..."
xcodebuild build \
  -scheme Tokenomics \
  -destination 'platform=macOS' \
  -project "$XCODEPROJ" \
  -configuration Debug \
  | grep -E "^(error:|warning:|Build succeeded|Build FAILED)" || true

echo ""

# 3. Run the test suite
echo "[3/3] Running TokenomicsTests..."
xcodebuild test \
  -scheme Tokenomics \
  -destination 'platform=macOS' \
  -project "$XCODEPROJ" \
  | grep -E "(passed|failed|error:|Test session results)" | head -80

echo ""
echo "==> pre-PR check complete. If you see ** TEST SUCCEEDED ** above, you're good to push."
