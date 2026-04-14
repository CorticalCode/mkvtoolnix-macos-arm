# Changelog

## Correction Notice (2026-04-13)

Builds b003 and b004 claimed Qt 6.10.2 but were built against Qt 6.10.0 due to a version mismatch bug. A stale Qt 6.10.0 build directory masked the error on ARM. The bug was discovered when attempting an Intel build on a clean machine. Releases r2 and r3 have been removed. See the b003/b004 entries below for details.

The build process now includes pre-build and post-build verification, a proven dependency cache, and comprehensive workspace management to prevent this from happening again.

## Build Optimization (2026-04-14)

Compiler and linker optimization flags for smaller, faster binaries.

**Changes:**
- Added `-O2` to CFLAGS/CXXFLAGS — autotools deps (Boost, FLAC, libogg, etc.) were building at `-O0`
- Added `-Wl,-dead_strip` to LDFLAGS — removes unreachable code at link time
- Added `-DCMAKE_BUILD_TYPE=Release` to cmark build
- Restored `qt-patches/001-fix-arm-yield-declaration.patch` — Qt 6.10.2 does NOT include the arm_acle.h fix (was incorrectly retired; exposed by `--full` rebuild)

**Size impact:** App 78.5 -> 72.0 MB (8%), DMG 33.9 -> 31.9 MB (6%)

---

## Build Cache Architecture (2026-04-14)

Comprehensive refactor of the build system to prevent stale artifact contamination.

**New features:**
- Proven cache system: known-good compiled packages stored per-architecture (`~/opt/proven/arm/`, `~/opt/proven/intel/`)
- Complete workspace wipe before every build (preserves proven/ and source/)
- Smart restore: auto-detects proven cache and only rebuilds mkvtoolnix when all deps are available
- Comprehensive post-build verification: Qt version, architecture of all binaries/dylibs, duplicate dylib scan, size sanity check, bundle inventory
- Atomic promotion: archive proven to LFS, directory-swap replacement (no empty state on interruption)
- Stale directory cleanup for all dependencies, not just Qt
- DocBook XSL included in cache flow
- EXPECTED_PACKAGES derived dynamically from specs.sh (single source of truth)
- Build log tee'd to timestamped file, build report with summary
- ERR trap prints line number on failures

**Build flags:**
- `./build-local.sh release-98.0` — smart build (wipe, restore from proven, build missing)
- `./build-local.sh release-98.0 --full` — force full rebuild from source
- `./build-local.sh release-98.0 --promote` — promote current build to proven cache

---

## v98.0-arm64-b005 (2026-04-13)

Genuine Qt 6.10.2 build with version verification.

**Changes:**
- Fixed QTVER mismatch — config.local.sh now sets QTVER=6.10.2 to match specs-updates.patch
- Added pre-build verification: fails fast if QTVER doesn't match specs.sh
- Added stale directory cleanup: removes old Qt build directories before extraction
- Added post-build verification: confirms Qt version in binary and architecture
- Cleaned stale Qt 6.10.0 artifacts from build environment

**Verification output:**
- Pre-build: QTVER=6.10.2 matches specs.sh
- Post-build: binary links Qt 6.10.2 (confirmed)
- Architecture: arm64

**Active patches (4):**
- `qt6-cmake-install.patch` -- Qt6 install fix
- `specs-updates.patch` -- Qt 6.10.2 bump + zlib URL fix
- `remove-printsupport.patch` -- drop unused Qt module
- `strip-dylibs.patch` -- strip debug symbols

---

## v98.0-arm64-b004 (2026-04-13) — RETRACTED

Remove unused Qt PrintSupport module. Consolidate specs patches.

**Note:** This build claimed Qt 6.10.2 but was built against Qt 6.10.0 due to QTVER mismatch. The stale Qt 6.10.0 build directory was used instead of the 6.10.2 source. Release r3 was removed.

---

## v98.0-arm64-b003 (2026-04-13) — RETRACTED

Bump Qt from 6.10.0 to 6.10.2.

**Note:** This build claimed Qt 6.10.2 but was built against Qt 6.10.0 due to QTVER mismatch. A stale Qt 6.10.0 directory in the compile workspace masked the error. Release r2 was removed.

**Root cause:** Our specs-updates.patch correctly changed the Qt download URL and checksum to 6.10.2, but upstream's config.sh still set QTVER=6.10.0. The build_qt function uses QTVER for the directory name. On ARM, the old 6.10.0 directory still existed from the first build, so the cd succeeded — silently building from old source. On Intel (clean machine), there was no stale directory and the build correctly failed.

---

## v98.0-arm64-b002 (2026-04-13)

Strip debug symbols from Qt shared libraries and plugins.

**Size impact:**
- Uncompressed app: 84.8 MB -> 78.9 MB (6 MB saved, 7% reduction)
- DMG: 34.9 MB -> 34.0 MB (0.9 MB saved, compressed masks most of the gain)

**Patch added:**
- `strip-dylibs.patch` -- strip -x on all dylibs after library path fixup

---

## v98.0-arm64-b001 (2026-04-13)

First successful build of MKVToolNix 98.0 for macOS Apple Silicon.

**Built against:**
- MKVToolNix 98.0 (upstream tag `release-98.0`)
- Qt 6.10.0
- Boost 1.88.0
- macOS 26.4.1, Apple clang 21.0.0, Xcode
- ARM64 (Apple Silicon), deployment target macOS 13+

**Patches applied:**
- `qt6-cmake-install.patch` -- fix Qt6 install step in build.sh
- `zlib-url-fix.patch` -- fix dead zlib download URL
- `qt-patches/001-fix-arm-yield-declaration.patch` -- fix Qt6 ARM `__yield` compilation error
- `config.local.sh` -- disable code signing, set 12 build threads
