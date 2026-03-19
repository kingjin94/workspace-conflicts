# uv Workspace Conflicts Demo

This repository demonstrates how `uv.lock` file size scales with conflict declarations across multiple packages in a workspace.

## Setup

- Root workspace with 4 sub-packages (A, B, C, D)
- Each package has `prod` and `non-prod` extras:
  - `prod` extra includes `psycopg2>=2.9.0`
  - `non-prod` extra includes `psycopg2-binary>=2.9.0`
- Root workspace aggregates all sub-package extras

## Branches

### `repro/silent-lock-repair` — MWE for silent `uv.lock` inconsistency and auto-repair

An inconsistent `uv.lock` — where the resolved `[[package]]` version contradicts
a `specifier` in `[package.metadata]` — is accepted silently by `uv lock --check`
and by plain `uv lock`. Only `uv lock --refresh` detects and repairs it, without
any warning or explanation.

**Commit history on this branch:**
1. Adds `coverage` as a dev dependency (`package-a: ==7.12.0`, `package-b: >=7.12.0`)
2. Renovate bumps both to `7.13.4`, `uv lock` resolves consistently to `7.13.4`
3. Tests fail; a partial rollback reverts `package-b` specifier to `>=7.12.0` and
   manually downgrades the resolved `[[package]]` entry to `7.12.0`, but misses
   the `==7.13.4` pin in `package-a` — leaving the lock inconsistent
4. Repro script demonstrates the bug

```bash
git checkout repro/silent-lock-repair
bash repro-silent-lock-repair.sh
```

Expected output (steps 2 and 3 **should** fail but don't):
```
=== Step 2: uv lock --check (should catch the inconsistency) ===
Resolved 8 packages in 6ms
Exit code: 0  ← exits 0 despite inconsistency (FALSE NEGATIVE)

=== Step 3: uv lock (no change — uses cache, inconsistency survives) ===
Resolved 8 packages in 4ms
Exit code: 0
No changes — broken lock survives plain 'uv lock'

=== Step 4: uv lock --refresh (silently repairs — no warning issued) ===
Resolved 8 packages in 191ms
Updated coverage v7.12.0 -> v7.13.4
Exit code: 0
```

Tested on **uv 0.10.11**.

The practical risk: CI using `uv lock --check` gives a false green while resolving
the wrong version. Any subsequent `uv lock --refresh` silently introduces the
correct (but different) version with no explanation.

### `master` - With conflicts in all packages
All packages declare their extras as conflicting:
```toml
[tool.uv]
conflicts = [
    [
        { extra = "prod" },
        { extra = "non-prod" },
    ],
]
```
**Lock file size: 45K**

### `without-subpackage-conflicts` - Without conflicts in sub-packages
Only the root workspace declares conflicts. Sub-packages have the same extras but without conflict declarations.

**Lock file size: 28K**

## Impact

Declaring conflicts in each sub-package increases the lock file size by **38%** (17K).

The `uv.lock` file contains a separate conflict entry for each package:
```toml
conflicts = [[
    { package = "package-a", extra = "non-prod" },
    { package = "package-a", extra = "prod" },
], [
    { package = "package-b", extra = "non-prod" },
    { package = "package-b", extra = "prod" },
], [
    { package = "package-c", extra = "non-prod" },
    { package = "package-c", extra = "prod" },
], [
    { package = "package-d", extra = "non-prod" },
    { package = "package-d", extra = "prod" },
], [
    { package = "workspace-demo", extra = "non-prod" },
    { package = "workspace-demo", extra = "prod" },
]]
```

## Issue

When workspace members define conflicting extras that are aggregated by the root workspace, it seems unnecessary to duplicate the conflict declarations in the lock file. The root workspace conflict should be sufficient to enforce the constraints across all packages.

This becomes particularly problematic in larger workspaces with many packages, where the lock file can grow significantly just from conflict metadata.

### Trade-off: Root-level conflicts allow sub-package conflicts

While declaring conflicts only at the root workspace level reduces lock file size, it has a significant drawback: **individual sub-packages can still install conflicting dependencies** when synced independently.

**Example on `without-subpackage-conflicts` branch:**

```bash
$ uv sync --all-extras --package=package-a
Resolved 7 packages in 4ms
Prepared 1 package in 953ms
Installed 1 package in 8ms

$ uv pip list
Package         Version Editable project location
--------------- ------- -------------------------
package-a       0.1.0   (editable)
psycopg2        2.9.11
psycopg2-binary 2.9.11
```

Both `psycopg2` and `psycopg2-binary` are installed, which is problematic as these packages conflict at runtime.

On the `master` branch with sub-package conflicts, this would fail:
```bash
$ uv sync --all-extras --package=package-a
error: Extras `non-prod` and `prod` are incompatible with the declared conflicts: {`package-a[non-prod]`, `package-a[prod]`}
```

### The dilemma

- **With conflicts in sub-packages**: Lock file size increases significantly, but individual packages are protected from conflicting dependencies
- **Without conflicts in sub-packages**: Smaller lock file, but individual packages can install conflicting dependencies, potentially causing runtime issues

## Reproduce

```bash
# Compare lock file sizes
git checkout master
uv lock
ls -lh uv.lock  # 45K

git checkout without-subpackage-conflicts
uv lock
ls -lh uv.lock  # 28K
```
