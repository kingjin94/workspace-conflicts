#!/usr/bin/env bash
# Reproduction script for: uv lock --check --refresh false positive
# in a workspace with conflicting extras
#
# Expected: both commands agree on whether the lockfile is up to date
# Actual:   --check --refresh reports "needs to be updated" but --refresh
#           alone produces zero changes

set -euo pipefail

echo "=== uv version ==="
uv --version

echo ""
echo "=== Step 1: uv lock --refresh (writes result) ==="
uv lock --refresh
echo "Exit code: $?"

echo ""
echo "=== Step 2: git diff uv.lock (should be empty) ==="
git diff --exit-code uv.lock && echo "No changes — lockfile is up to date" || echo "CHANGED"

echo ""
echo "=== Step 3: uv lock --check --refresh (should also pass) ==="
uv lock --check --refresh
echo "Exit code: $?"
