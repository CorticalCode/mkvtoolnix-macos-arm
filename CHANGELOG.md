# Changelog

## Housekeeping & tooling (2026-04-19)

**Release management:**
- Retracted [v98.0-b2026.04.1](../../releases/tag/v98.0-b2026.04.1) — both DMGs removed and replaced with a `RETRACTED.txt` marker explaining the Homebrew library-leak crash. Tag preserved for historical reference (still referenced in `PATCHES.md`).

**Documentation:**
- Added `proven/NOTICE.md` — third-party attribution for every library bundled into the proven dependency cache. Covers both `proven/arm/` and `proven/intel/`. Addresses GPL/LGPL source-availability and permissive-license attribution for repo-hosted compiled binaries.
- README: replaced the download bullet list with a release table showing download links and sizes per architecture.
- README + `docs/build-workflow.md`: documented the shared `.build-counter-{arm,intel}` files — why they're tracked and how to reset on a fresh clone.

**Build-script guards:**
- `build-local.sh` now refuses `--promote` on any branch except `main` — prevents accidental `proven/` commits from experimental work (commit `cfdf450`).
- `build-local.sh` now skips the release-ready DMG copy on non-main branches — prevents experimental builds from leaving a file in `release/` that looks like a shippable artifact (commit `22061b4`).

**Upstream cross-references:**
- `PATCHES.md` now links each build patch to its upstream Codeberg issue: [#6205](https://codeberg.org/mbunkus/mkvtoolnix/issues/6205), [#6206](https://codeberg.org/mbunkus/mkvtoolnix/issues/6206), [#6207](https://codeberg.org/mbunkus/mkvtoolnix/issues/6207), [#6208](https://codeberg.org/mbunkus/mkvtoolnix/issues/6208) — all closed `res:fixed/implemented`, `fixed-in-version/99.0`. Local patches remain active until 99.0 releases.

**CI & security scanning:**
- Added explicit `permissions:` block to the CI workflow — resolves CodeQL alert #1 (commit `5bff010`).
- Added gitleaks configuration for custom secret and privacy scanning (public `bc3da08`, private `eb119a9`).
- Tidied `.gitignore` (commits `82e5b19`, `414b027`).

---

## Build System: LFS On-Demand (2026-04-15)

Proven dependency cache is now opt-in. Cloning the repo no longer downloads ~534 MB of pre-built dependency archives.

**What changed:**
- Added `.lfsconfig` with `fetchexclude = proven/**` — clones are now ~1 MB
- New `--restore-cache` flag: pulls pre-built deps from LFS for your architecture, copies to local build cache, cleans up repo
- New `--cleanup-lfs` flag: restores `proven/` to pointer files and prunes LFS cache (for existing clones)
- `--promote` now cleans up repo LFS objects after committing
- `cleanup_repo_lfs` uses bounded `dd`-based LFS header detection (safe on large binaries)
- Failed `git lfs pull` is caught and repo is restored to clean pointer state
- `restore_from_proven` validates all packages exist before untarring (no partial restore)
- CI workflow updated to work with `.lfsconfig` (explicit LFS restore instead of `lfs: true`)

**New flags:**
- `--restore-cache` — pull proven deps from LFS to local cache and clean up (no tag required)
- `--cleanup-lfs` — restore proven/ to pointer files and prune LFS cache (no tag required)

**Documentation:**
- New `docs/build-workflow.md` with Mermaid flowcharts covering all build modes
- Updated `docs/proven-cache.md` and `README.md` with `--restore-cache` workflow
- Existing clone cleanup instructions (scripted and manual)

**Known limitation:** On clones that predate `.lfsconfig`, `--cleanup-lfs` cannot automatically restore pointer files due to a Git index optimization. The script detects this and prints manual fix instructions. See [docs/lfs-migration.md](docs/lfs-migration.md) for the one-time migration steps.

**Multi-agent review:** Three rounds of cross-provider review (Codex + Gemini) identified and fixed: function-before-define crash, unreliable pointer detection, single-arch cleanup, circular clone dependency, interrupted pull recovery, partial restore on stale cache, unbounded binary reads, documentation inconsistencies, and the Git index optimization that prevents automatic pointer restoration on existing clones.

---

## v98.0-b2026.04.3 (2026-04-15) — Current Release

Critical fix for Homebrew library leak that caused DYLD crashes on launch.

**What was broken:** Qt was linking against Homebrew system libraries (double-conversion, pcre2, zstd, libpng, md4c, freetype) instead of its bundled copies. Any user without those same Homebrew packages would get a "library not loaded" crash. All previous builds were affected.

**Fix (belt and suspenders):**
- Removed `-force-pkg-config` and `-pkg-config` from Qt configure, restoring Qt 6's default macOS behavior where Homebrew prefixes are excluded from library search paths
- Added `-force-bundled-libs` to force Qt's bundled third-party libraries, and `-no-feature-zstd` to disable zstd (not bundled by Qt, falls back to zlib)

**Downloads:**
- Apple Silicon (arm64): `MKVToolNix-98.0-macos-apple-silicon.dmg` — 77.3 MB app, 36 MB DMG
- Intel (x86_64): `MKVToolNix-98.0-macos-intel.dmg` — 81.9 MB app, 38 MB DMG

**Build system improvements:**
- Post-build Homebrew/external library leak detection (scans all dylibs for non-system references)
- App size verification now uses actual file bytes (decimal MB) to match Finder
- Build timing (start, finish, elapsed) added to build reports
- Build logs copied to `logs/` directory with build number
- Internal DMG filename reordered: build number before branch name for chronological sorting
- Workspace cleanup now includes compile directory to prevent stale build failures
- Output directories renamed: `dist/` → `build/` (internal) + `release/` (clean-named)

**Verified:** Tested in a clean virtual machine — previous builds crash on launch, updated builds run without issues.

**Filed upstream:** [Codeberg #6208](https://codeberg.org/mbunkus/mkvtoolnix/issues/6208)

**Upstream news:** Patches #6205, #6206, #6207 (Qt6 cmake install, debug symbol stripping, cmark optimization) were merged into upstream MKVToolNix v99.0.

**Other improvements:**
- CI workflow updated: CalVer tagging, `apple-silicon` filename convention, leak detection in verification
- DMG release filenames standardized to `apple-silicon` / `intel`

**Reported by:** Adam, Ryu67, and Vek239 on the MKVToolNix forum.

---

## v98.0-b2026.04.2 (2026-04-14)

Ad-hoc code signing for macOS Sequoia 15.1+ compatibility. Both Apple Silicon and Intel builds updated.

**Changes:**
- App is now ad-hoc signed (`SIGNATURE_IDENTITY="-"`) which should restore the "Open Anyway" flow on macOS Sequoia 15.1+ where completely unsigned apps are blocked
- Previously, users on Sequoia had no way to open the app through normal macOS UI

---

## v98.0-b2026.04.1 (2026-04-14)

> ⚠️ **RETRACTED 2026-04-19** — this build crashes on launch unless specific Homebrew packages are present. Both DMG assets have been removed from the GitHub release. Use [v98.0-b2026.04.3](../../releases/tag/v98.0-b2026.04.3) instead. See `proven/NOTICE.md`, this file's Housekeeping entry for 2026-04-19, and upstream issue [#6208](https://codeberg.org/mbunkus/mkvtoolnix/issues/6208) for the full root cause.

First combined Apple Silicon + Intel release with optimized builds.

**Downloads:**
- Apple Silicon (arm64): 72 MB app, 31.9 MB DMG
- Intel (x86_64): 86.6 MB app, 39 MB DMG

**Built with:** Qt 6.10.2, Boost 1.88.0, macOS 13+ deployment target.

**Active patches (6):**
- `qt6-cmake-install.patch` -- Qt6 cmake install fix
- `specs-updates.patch` -- Qt 6.10.2 bump + zlib URL fix
- `remove-printsupport.patch` -- drop unused Qt module
- `strip-dylibs.patch` -- strip debug symbols from dylibs
- `cmark-release-build.patch` -- CMAKE_BUILD_TYPE=Release for cmark
- `qt-patches/001-fix-arm-yield-declaration.patch` -- ARM arm_acle.h include for Qt

**Build system improvements:**
- Ad-hoc code signing for macOS Sequoia 15.1+ compatibility
- Proven dependency cache with per-architecture storage (Apple Silicon / Intel)
- Compiler optimization (-O2) and linker dead-stripping for all dependencies
- Comprehensive post-build verification (Qt version, architecture, duplicate dylibs, size)
- Build logging, reporting, and error trapping
- Dynamic EXPECTED_PACKAGES derivation from specs.sh

**Note on earlier releases:** During development, multiple intermediate releases (r1 through r5 for ARM, r1 for Intel) were published and subsequently pulled as the build process was refined and optimized. Only this final verified release is published. Previous builds are available on request.

---

## Development History (2026-04-13 to 2026-04-14)

### Build optimization (2026-04-14)

- Added `-O2` to CFLAGS/CXXFLAGS — autotools deps were building at `-O0`
- Added `-Wl,-dead_strip` to LDFLAGS — removes unreachable code at link time
- Added `-DCMAKE_BUILD_TYPE=Release` to cmark build
- Restored `qt-patches/001-fix-arm-yield-declaration.patch` — Qt 6.10.2 does NOT include the arm_acle.h fix (was incorrectly retired; exposed by `--full` rebuild)
- Size impact: App 78.5 -> 72.0 MB (8%), DMG 33.9 -> 31.9 MB (6%)

### Script hardening (2026-04-14)

- Multi-reviewer audit identified 33 issues across correctness, portability, and robustness
- All 7 P1 and 14 P2 issues fixed: set -e safety, NULL_GLOB guards, alias isolation, clone tag verification, promote validation, verification hardening
- Shell interpreter guard, improved error trapping, INT/TERM signal handling

### Build cache architecture (2026-04-14)

- Proven cache system with per-architecture storage
- Complete workspace wipe before every build
- Smart restore: builds only mkvtoolnix when all deps are cached (~15 min vs ~1-3 hrs)
- Atomic promotion with Git LFS archiving
- Comprehensive post-build verification

### Qt version mismatch bug (2026-04-13)

Builds b003 and b004 claimed Qt 6.10.2 but were built against Qt 6.10.0 due to a QTVER mismatch. A stale Qt 6.10.0 build directory masked the error on ARM. Discovered when the Intel build (clean machine) failed correctly. Root cause: Qt version specified in multiple locations with no validation. Fixed with pre-build verification and workspace wipe.

### Initial builds (2026-04-13)

- b001: First successful ARM build (Qt 6.10.0, 84.8 MB app)
- b002: Added debug symbol stripping (78.9 MB app)
- b003-b004: RETRACTED — Qt version mismatch
- b005: Duplicate dylib bug (101.8 MB app) — retracted
- b006-b008: Clean builds with build cache architecture (78.5 MB app)
