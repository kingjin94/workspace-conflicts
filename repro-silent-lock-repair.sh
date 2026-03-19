#!/usr/bin/env bash
# Reproduction script for: inconsistent uv.lock passes `uv lock --check`
# silently, then auto-repairs without warning on `uv lock --refresh`.
#
# Setup (see commit history):
#   - package-a declares coverage==7.13.4 in pyproject.toml
#   - package-b declares coverage>=7.12.0 in pyproject.toml
#   - uv.lock [[package]] coverage resolves to 7.12.0  ← INCONSISTENT
#
# The inconsistency was introduced by manually downgrading the resolved
# [[package]] entry in uv.lock while only partially reverting specifiers:
# the ">=" form in package-b was reverted, but the "==" form in package-a
# was missed — leaving package-a declaring ==7.13.4 against a 7.12.0 resolve.
#
# Expected: `uv lock --check` catches the inconsistency (exit 1)
# Actual:   `uv lock --check` exits 0 — then `uv lock --refresh` silently fixes it

set -euo pipefail

echo "=== uv version ==="
uv --version

echo ""
echo "=== Current state of uv.lock ==="
echo "Resolved version:"
grep -A1 'name = "coverage"' uv.lock | grep "^version"
echo ""
echo "Declared specifiers in [package.metadata] inside uv.lock:"
grep 'coverage.*specifier' uv.lock

echo ""
echo "=== Step 1: Show the contradiction ==="
echo "package-a/pyproject.toml declares:"
grep "coverage" packages/package-a/pyproject.toml
echo "package-b/pyproject.toml declares:"
grep "coverage" packages/package-b/pyproject.toml
echo ""
RESOLVED=$(grep -A1 'name = "coverage"' uv.lock | grep '^version' | cut -d'"' -f2)
echo "uv.lock resolves coverage to: $RESOLVED"
echo ""
echo ">>> package-a pins ==7.13.4 but uv.lock has $RESOLVED — INCONSISTENT"

echo ""
echo "=== Step 2: uv lock --check (should catch the inconsistency) ==="
uv lock --check
echo "Exit code: $?  ← exits 0 despite inconsistency (FALSE NEGATIVE)"

echo ""
echo "=== Step 3: uv lock (no change — uses cache, inconsistency survives) ==="
uv lock
echo "Exit code: $?"
git diff --exit-code uv.lock && echo "No changes — broken lock survives plain 'uv lock'" || echo "CHANGED"

echo ""
echo "=== Step 4: uv lock --refresh (silently repairs — no warning issued) ==="
uv lock --refresh
echo "Exit code: $?"

echo ""
echo "=== Step 5: git diff uv.lock (lock was silently changed!) ==="
git diff uv.lock | grep "^[+-].*\"7\.1[23]" | grep -v "^---\|^+++" || true
echo ""
RESOLVED_AFTER=$(grep -A1 'name = "coverage"' uv.lock | grep '^version' | cut -d'"' -f2)
echo "coverage: $RESOLVED -> $RESOLVED_AFTER"
echo ""
echo ">>> Upgrade happened silently. 'uv lock --check' passed with the broken"
echo ">>> 7.12.0 resolution. Plain 'uv lock' also kept it broken."
echo ">>> Only 'uv lock --refresh' discovered and fixed it — with no warning."
