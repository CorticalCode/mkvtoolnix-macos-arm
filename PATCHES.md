# Build Patches — What, Why, and How

Living document tracking every modification made to build MKVToolNix on macOS Apple Silicon, the problems encountered, and how they were resolved.

## Build status

The build process is under active improvement. A version mismatch bug was discovered on 2026-04-13 where builds b003 and b004 claimed Qt 6.10.2 but were silently built against Qt 6.10.0. Pre-build and post-build verification checks have been added to prevent this. A more resilient build cache architecture is being designed.

## Size progression

| Build | DMG | App on disk | Qt actual | Notes |
|-------|-----|-------------|-----------|-------|
| b001 (baseline) | 34.9 MB | 84.8 MB | 6.10.0 | verified |
| b002 (+ strip dylibs) | 34.0 MB | 78.9 MB | 6.10.0 | verified |
| b003 (+ Qt bump) | 34.0 MB | 78.9 MB | **6.10.0** | RETRACTED — claimed 6.10.2 |
| b004 (+ no PrintSupport) | 33.9 MB | 78.4 MB | **6.10.0** | RETRACTED — claimed 6.10.2 |
| b005 (genuine 6.10.2) | pending | pending | 6.10.2 | verified by post-build check |

---

## Active patches (4)

### 1. Qt6 cmake install (`patches/qt6-cmake-install.patch`)

**File patched:** `packaging/macos/build.sh` line 373

**Problem:** The upstream `build_qt` function compiles Qt6 using `cmake --build` but then tries to install with `make DESTDIR=TMPDIR install`. Qt6's build system is fully cmake-based -- the Makefile install target doesn't work correctly for Qt6's module layout.

**Root cause:** Qt transitioned from qmake to cmake as its build system. The upstream MKVToolNix build script was written when `make install` still worked. Qt6's cmake build generates install rules that are only accessible via `cmake --install`.

**Fix:** Replace the install command in `build_qt`:
```
- build_tarball command "make DESTDIR=TMPDIR install"
+ build_tarball command "cmake --install . --prefix TMPDIR${TARGET}"
```

**Note:** Only the Qt-specific line (line 373) is patched. The generic `build_package` function (line 150) has the same `make install` pattern but it works fine for other cmake packages (cmark, etc.) because they generate proper Makefile install targets.

**Source:** MKVToolNix forum thread -- multiple users reported this fix for Qt6 builds.

---

### 2. Specs updates (`patches/specs-updates.patch`)

**File patched:** `packaging/macos/specs.sh`

This patch combines two changes to the same file to avoid context conflicts when applied in sequence.

**2a. Dead zlib download URL**

**Problem:** Build fails at zlib step. `curl` downloads a 355-byte HTML error page. Checksum verification catches it.

**Root cause:** `https://zlib.net/zlib-1.3.1.tar.xz` returns 404. zlib removes old tarballs when new versions release.

**Fix:** Switch to GitHub releases mirror (same file, same checksum):
```
- https://zlib.net/zlib-1.3.1.tar.xz
+ https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.xz
```

**Shelf life:** Unnecessary when upstream bumps zlib or fixes the URL.

**2b. Qt version bump to 6.10.2**

**Problem:** Qt 6.10.0 has a compilation bug on ARM (`__yield` without `arm_acle.h` include) and community-reported UI issues (progress bar, preferences truncation, pane resizing, macOS 26 rendering).

**Fix:** Bump Qt from 6.10.0 to 6.10.2 with updated download URL and SHA256 checksum. Qt 6.10.2 includes the `arm_acle.h` fix upstream, eliminating the need for our separate Qt source patch.

---

### 3. Remove unused PrintSupport (`patches/remove-printsupport.patch`)

**File patched:** `packaging/macos/build.sh` (two locations)

**Problem:** Qt PrintSupport module (453 KB) is compiled and bundled in the app, but MKVToolNix has zero print functionality -- no references to `QPrinter`, `QPrintDialog`, or `QPrintPreview` anywhere in the source.

**Root cause:** The upstream Qt configure line doesn't explicitly exclude PrintSupport. It disables cups but not the broader print module.

**Fix:**
1. Add `-no-feature-printsupport` to the Qt configure arguments
2. Remove `PrintSupport*.dylib` from the dylib copy in `build_dmg`

**Verification:** Traced all Qt class imports in `src/mkvtoolnix-gui/` -- confirmed zero PrintSupport usage. Verified the module is absent from the built app bundle.

**Size impact:** 453 KB uncompressed, 138 KB compressed in DMG.

---

### 4. Strip debug symbols from dylibs (`patches/strip-dylibs.patch`)

**File patched:** `packaging/macos/build.sh` after line 512

**Problem:** Upstream strips the five mkv binaries but not the Qt shared libraries or plugins. Debug symbols in bundled third-party libraries add ~6 MB with no value in a distribution build.

**Root cause:** The upstream build was designed for a developer who could debug against these libraries.

**Fix:** Add `strip -x` after `fix_library_paths.sh` runs, targeting all dylibs in the app bundle. The `-x` flag removes local symbols (debug info) while preserving global symbols needed for dynamic linking.

**Why after fix_library_paths.sh:** Library path rewriting modifies the dylib binaries. Stripping before path fixup could remove relocation info needed by `install_name_tool`.

**Size impact:** 6 MB uncompressed (84.8 -> 78.9 MB), 0.9 MB compressed in DMG.

---

## Config overlay (`config/config.local.sh`)

**Not a patch** -- a config file sourced by the upstream build system.

- `SIGNATURE_IDENTITY=""` -- disables code signing (no Apple Developer cert)
- `DRAKETHREADS=12` -- parallel build threads (default is 4, machine has 14 cores)

---

## Build script fixes (in `build-local.sh`)

**`command cp` instead of `cp`:** macOS zsh aliases `cp` to `cp -i` (interactive). In non-interactive shells, `cp -i` prompts for overwrite confirmation, gets no input, and defaults to "no". `command cp` bypasses the alias.

**`git checkout -- .` before patching:** On re-runs, the source tree may have patches already applied. Resetting first ensures a clean slate.

**`mkdir -p ~/opt/include ~/opt/lib`:** The upstream build scripts assume these directories exist.

**Smart dep caching:** Auto-detects 14 cached dependency packages in `~/opt/packages/`. If all present, restores from cache and only builds mkvtoolnix (minutes instead of hours).

---

## Retired patches

### Qt6 ARM `__yield` declaration (formerly `patches/qt-patches/001-fix-arm-yield-declaration.patch`)

**Retired:** 2026-04-13
**Reason:** Fixed upstream in Qt 6.10.2. The identical `arm_acle.h` include was added to the Qt source.

**Original problem:** Qt6's `qyieldcpu.h` called `__yield()` on ARM without including `<arm_acle.h>`. Apple clang 21 treated this as `-Werror`. Qt's Bootstrap target ignored environment `CXXFLAGS`, so flag workarounds didn't reach it. Patching the Qt source directly was the proper fix.

---

## Issues investigated but not requiring patches

**`-no-rpath` crash:** Flagged in research as a common Qt6 build failure. Not present in v98.0 -- already removed upstream.

**Dependency build failures on ARM:** No ARM-specific issues. All 15 dependencies build cleanly on Apple Silicon.

**macOS 13 deployment target:** No issues. Binaries built on macOS 26 with `MACOSX_DEPLOYMENT_TARGET=13` work correctly.

**Stale dependency URLs:** Checked all 17 URLs. Only zlib was dead (patched above). All others return 200.

---

## Issues discovered during development

### QTVER mismatch (discovered 2026-04-13)

**Severity:** High — caused mislabeled releases (r2, r3 removed)

**Problem:** specs-updates.patch changed specs.sh to download Qt 6.10.2, but QTVER in upstream config.sh remained 6.10.0. The build_qt function uses QTVER for the directory name after extraction. On ARM, a stale qt-everywhere-src-6.10.0 directory masked the error — builds appeared to succeed but used old Qt source. On Intel (clean machine), the directory didn't exist and the build correctly failed.

**Root cause:** Qt version is specified in multiple locations (specs.sh, config.sh, build-local.sh EXPECTED_PACKAGES) with no validation that they agree.

**Fix applied:**
- Set QTVER=6.10.2 in config.local.sh
- Updated EXPECTED_PACKAGES in build-local.sh
- Added pre-build check: verifies QTVER matches specs.sh, fails fast on mismatch
- Added stale Qt directory cleanup before extraction
- Added post-build check: confirms Qt version in the built binary

**Lesson:** Stale build artifacts can silently produce incorrect builds. Version changes must be validated end-to-end, not just at the download step. A build cache architecture with clean workspaces is being designed to prevent this class of error permanently.
