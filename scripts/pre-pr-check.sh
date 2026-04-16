#!/usr/bin/env bash
# pre-pr-check.sh — run before opening a PR or cutting a release
# Fails fast on any error. Exit code 0 = all checks passed.
#
# Flags:
#   SKIP_INTEGRATION=1  — skip the integration test phase (useful in CI without
#                         App Group entitlements where widget sync tests are skipped anyway)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="$PROJECT_ROOT/Tokenomics.xcodeproj"
SKIP_INTEGRATION="${SKIP_INTEGRATION:-0}"

echo "==> Tokenomics pre-PR check"
echo ""

# 1. Regenerate project from project.yml to catch any drift
echo "[1/4] Regenerating Xcode project from project.yml..."
xcodegen generate --spec "$PROJECT_ROOT/project.yml" --project "$PROJECT_ROOT"
echo "      OK"
echo ""

# 2. Build (catches compilation errors before running tests)
echo "[2/4] Building Tokenomics (Debug)..."
xcodebuild build \
  -scheme Tokenomics \
  -destination 'platform=macOS' \
  -project "$XCODEPROJ" \
  -configuration Debug \
  | grep -E "^(error:|warning:|Build succeeded|Build FAILED)" || true

echo ""

# 3. Run the unit test suite
echo "[3/4] Running TokenomicsTests (unit tests)..."
set +o pipefail
xcodebuild test \
  -scheme Tokenomics \
  -destination 'platform=macOS' \
  -project "$XCODEPROJ" \
  | grep -E "(passed|failed|error:|Test session results)" | tail -20
UNIT_EXIT=${PIPESTATUS[0]}
set -o pipefail
if [ "$UNIT_EXIT" != "0" ]; then
  echo "Unit tests FAILED (xcodebuild exit $UNIT_EXIT)"
  exit 1
fi

echo ""

# 4. Run integration tests (skippable via SKIP_INTEGRATION=1)
if [ "$SKIP_INTEGRATION" = "1" ]; then
  echo "[4/4] Integration tests SKIPPED (SKIP_INTEGRATION=1)"
else
  echo "[4/4] Running TokenomicsIntegrationTests..."
  set +o pipefail
  xcodebuild test \
    -scheme TokenomicsIntegration \
    -destination 'platform=macOS' \
    -project "$XCODEPROJ" \
    | grep -E "(passed|failed|skipped|error:|Test session results)" | tail -20
  INTEGRATION_EXIT=${PIPESTATUS[0]}
  set -o pipefail
  if [ "$INTEGRATION_EXIT" != "0" ]; then
    echo "Integration tests FAILED (xcodebuild exit $INTEGRATION_EXIT)"
    exit 1
  fi
fi

echo ""
echo "==> pre-PR check complete. If you see ** TEST SUCCEEDED ** above, you're good to push."
