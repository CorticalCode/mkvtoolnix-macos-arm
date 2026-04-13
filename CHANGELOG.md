# Changelog

## v98.0-arm64-b002 (2026-04-13)

Strip debug symbols from Qt shared libraries and plugins.

**Size impact:**
- Uncompressed app: 84.8 MB -> 78.9 MB (6 MB saved, 7% reduction)
- DMG: 34.9 MB -> 34.0 MB (0.9 MB saved, compressed masks most of the gain)

**Patch added:**
- `strip-dylibs.patch` — strip -x on all dylibs after library path fixup

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
- `qt6-cmake-install.patch` — fix Qt6 install step in build.sh
- `zlib-url-fix.patch` — fix dead zlib download URL
- `qt-patches/001-fix-arm-yield-declaration.patch` — fix Qt6 ARM `__yield` compilation error
- `config.local.sh` — disable code signing, set 12 build threads
