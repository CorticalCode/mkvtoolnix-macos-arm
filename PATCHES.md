# Build Patches — What, Why, and How

Living document tracking every modification made to build MKVToolNix on macOS Apple Silicon, the problems encountered, and how they were resolved.

---

## 1. Qt6 cmake install (`patches/qt6-cmake-install.patch`)

**File patched:** `packaging/macos/build.sh` line 373

**Problem:** The upstream `build_qt` function compiles Qt6 using `cmake --build` but then tries to install with `make DESTDIR=TMPDIR install`. Qt6's build system is fully cmake-based — the Makefile install target doesn't work correctly for Qt6's module layout.

**Root cause:** Qt transitioned from qmake to cmake as its build system. The upstream MKVToolNix build script was written when `make install` still worked. Qt6's cmake build generates install rules that are only accessible via `cmake --install`.

**Fix:** Replace the install command in `build_qt`:
```
- build_tarball command "make DESTDIR=TMPDIR install"
+ build_tarball command "cmake --install . --prefix TMPDIR${TARGET}"
```

**Note:** Only the Qt-specific line (line 373) is patched. The generic `build_package` function (line 150) has the same `make install` pattern but it works fine for other cmake packages (cmark, etc.) because they generate proper Makefile install targets.

**Source:** MKVToolNix forum thread — multiple users reported this fix for Qt6 builds.

---

## 2. Dead zlib download URL (`patches/zlib-url-fix.patch`)

**File patched:** `packaging/macos/specs.sh` line 15

**Problem:** Build fails immediately at the zlib step. `curl` downloads a 355-byte HTML error page instead of the tarball. Checksum verification catches it:
```
File checksum failed: zlib-v1.3.1.tar.xz SHA256 expected 38ef96b... actual cc0b4e4...
```

**Root cause:** The upstream URL `https://zlib.net/zlib-1.3.1.tar.xz` returns 404. When zlib releases a new version, they remove old tarballs from their primary download location. The MKVToolNix specs.sh pins version 1.3.1 but the host no longer serves it.

**Fix:** Switch to the GitHub releases mirror which preserves all versions:
```
- https://zlib.net/zlib-1.3.1.tar.xz
+ https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.xz
```

**Verification:** Downloaded from both URLs and confirmed identical SHA256 checksum (`38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32`). Same file, different host.

**Shelf life:** This patch becomes unnecessary when upstream bumps to a newer zlib version with a working URL, or updates their mirror.

---

## 3. Qt6 ARM `__yield` declaration (`patches/qt-patches/001-fix-arm-yield-declaration.patch`)

**File patched:** `qtbase/src/corelib/thread/qyieldcpu.h` (inside Qt6 source)

**Problem:** Qt6 compilation fails at 6% with:
```
qyieldcpu.h:37:5: error: implicitly declaring library function '__yield'
  with type 'void ()' [-Werror,-Wimplicit-function-declaration]
```

**Root cause:** Qt6's `qyieldcpu.h` uses `__has_builtin(__yield)` to detect ARM yield support, and if true, calls `__yield()`. On Apple clang 21 (Xcode on macOS 26), `__has_builtin(__yield)` returns true — the compiler knows the intrinsic — but the function is only formally declared in `<arm_acle.h>`. Without that include, calling `__yield()` is an implicit function declaration. Combined with Qt's internal `-Werror`, this becomes a hard build failure.

**Why a flag workaround didn't work:** We first tried `-Wno-error=implicit-function-declaration` in `QT_CXXFLAGS`. This downgraded the error to a warning for most Qt targets. However, Qt's internal `Bootstrap` target (used to build Qt's own build tools like moc and rcc) compiles with hardcoded cmake flags that ignore environment `CXXFLAGS` entirely. The Bootstrap target still failed.

**Fix:** Patch the Qt source directly to add the missing include:
```c
#if defined(Q_PROCESSOR_ARM) && __has_include(<arm_acle.h>)
#  include <arm_acle.h>
#endif
```

This is the proper fix — the compiler's own error message suggested it: "include the header `<arm_acle.h>` or explicitly provide a declaration for `__yield`".

**Applied via:** Upstream build system's own `qt-patches/` mechanism. The `build_package` function in `build.sh` automatically applies patches from a `{package}-patches/` directory after extraction.

**Upstream status:** This is a Qt 6.10.0 bug with newer Apple clang. May be fixed in Qt 6.10.1+.

---

## 4. Config overlay (`config/config.local.sh`)

**Not a patch** — this is a config file sourced by the upstream build system.

**What it does:**
- `SIGNATURE_IDENTITY=""` — disables code signing (we don't have the developer's Apple cert)
- `DRAKETHREADS=12` — parallel build threads (default is 4, machine has 14 cores)

**Why SIGNATURE_IDENTITY matters:** The upstream `config.sh` hardcodes `SIGNATURE_IDENTITY="Developer ID Application: Moritz Bunkus (YZ9DVS8D8C)"`. Without blanking it, the DMG build step tries to codesign with a certificate we don't have and fails.

---

## Build script fixes (in `build-local.sh`)

**`command cp` instead of `cp`:** macOS zsh aliases `cp` to `cp -i` (interactive). In non-interactive shells (background builds), `cp -i` prompts for overwrite confirmation, gets no input, and defaults to "no" — silently skipping the file copy. `command cp` bypasses shell aliases.

**`git checkout -- .` before patching:** On re-runs, the source tree may have patches already applied. `git apply` fails on already-patched files. Resetting first ensures a clean slate.

**`mkdir -p ~/opt/include ~/opt/lib`:** The upstream build scripts assume these directories exist. Without them, the first dependency build fails looking for include paths.

---

## Issues investigated but not requiring patches

**`-no-rpath` crash:** Research flagged this as a common Qt6 build failure on macOS. Checked v98.0 — the flag is not present. Already removed in upstream.

**Dependency build failures on ARM:** No ARM-specific issues. All 15 dependencies (autoconf, automake, pkg-config, libiconv, cmake, ogg, vorbis, flac, zlib, gettext, cmark, gmp, boost, curl, docbook-xsl) build cleanly on Apple Silicon.

**macOS 13 deployment target:** No issues. Binaries built on macOS 26 with `MACOSX_DEPLOYMENT_TARGET=13` work correctly.

**Stale dependency URLs:** Checked all 17 dependency URLs. Only zlib was dead (patched above). All others return 200.
