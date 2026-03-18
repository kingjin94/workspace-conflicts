# uv Workspace Conflicts Demo

This repository demonstrates how `uv.lock` file size scales with conflict declarations across multiple packages in a workspace.

## Setup

- Root workspace with 4 sub-packages (A, B, C, D)
- Each package has `prod` and `non-prod` extras:
  - `prod` extra includes `psycopg2>=2.9.0`
  - `non-prod` extra includes `psycopg2-binary>=2.9.0`
- Root workspace aggregates all sub-package extras

## Branches

### `repro/uv-check-refresh-false-positive` — MWE for `uv lock --check --refresh` false positive

In a workspace where sub-packages declare conflicting extras, `uv lock --check --refresh`
reports "lockfile needs to be updated" even when `uv lock --refresh` produces zero changes.

```bash
git checkout repro/uv-check-refresh-false-positive
bash repro-check-refresh.sh
```

Expected output (steps 1 and 2 pass, step 3 **should** also pass but doesn't):
```
=== Step 1: uv lock --refresh (writes result) ===
Resolved 7 packages in 170ms
Exit code: 0

=== Step 2: git diff uv.lock (should be empty) ===
No changes — lockfile is up to date

=== Step 3: uv lock --check --refresh (should also pass) ===
Resolved 7 packages in 151ms
The lockfile at `uv.lock` needs to be updated, but `--check` was provided.
```

Steps 1 and 2 confirm the lockfile is genuinely up to date. Step 3 is a false positive.
Tested on **uv 0.10.11**. Related upstream issues: astral-sh/uv#13614, astral-sh/uv#16839.

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
