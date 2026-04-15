# Changelog

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

**Reported by:** Adam, Ryu67, and Vek239 on the MKVToolNix forum.

---

## v98.0-b2026.04.2 (2026-04-14)

Ad-hoc code signing for macOS Sequoia 15.1+ compatibility. Both Apple Silicon and Intel builds updated.

**Changes:**
- App is now ad-hoc signed (`SIGNATURE_IDENTITY="-"`) which should restore the "Open Anyway" flow on macOS Sequoia 15.1+ where completely unsigned apps are blocked
- Previously, users on Sequoia had no way to open the app through normal macOS UI

---

## v98.0-b2026.04.1 (2026-04-14)

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
