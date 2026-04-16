# mkvtoolnix-gui-macos

Unofficial macOS builds of [MKVToolNix GUI](https://mkvtoolnix.download/) for Apple Silicon and Intel.

The MKVToolNix developer no longer provides macOS binaries. The CLI tools (`mkvmerge`, `mkvextract`, `mkvpropedit`, `mkvinfo`) are available via `brew install mkvtoolnix`, but the GUI is not. This repo builds the full MKVToolNix GUI application from the official source.

**These are personal builds shared as-is.** No warranty, no guaranteed support, no SLA. If a build works for you, great. If it doesn't, the build scripts and patches are here so you can debug and fix it yourself. Issues and contributions are welcome but may not receive a timely response. For MKVToolNix bugs unrelated to this build, report them [upstream](https://codeberg.org/mbunkus/mkvtoolnix/issues).

## Download

Grab the latest `.dmg` for your architecture from [Releases](../../releases):

- **Apple Silicon** (M1/M2/M3/M4): `MKVToolNix-{version}-macos-apple-silicon.dmg`
- **Intel**: `MKVToolNix-{version}-macos-intel.dmg`

These are separate architecture-specific builds, not a universal binary. Make sure to download the correct version for your Mac. Installing the wrong architecture will produce an error on launch.

**Note:** The DMGs are ad-hoc signed but not notarized. On macOS Sequoia and newer, you may need to allow the app in System Settings > Privacy & Security, or run:
```
xattr -cr /Applications/MKVToolNix*.app
```

## Build locally

Requirements: Xcode CLI tools, ~10 GB disk space, 1-3 hours (first build; subsequent builds reuse cached dependencies and take ~15 minutes).

```sh
git clone https://github.com/corticalcode/mkvtoolnix-gui-macos.git
cd mkvtoolnix-gui-macos

# Optional: pull pre-built dependencies to skip the 1-3 hour dep build
./build-local.sh --restore-cache

./build-local.sh release-98.0
```

The DMG will be at `~/tmp/compile/MKVToolNix-98.0.dmg`.

Use `--restore-cache` to pull pre-built dependencies from Git LFS (~15 min build). Omit it to build everything from source (~1-3 hours). Use `--full` to force a complete rebuild. See [docs/proven-cache.md](docs/proven-cache.md) for details.

> **Cloned before April 2026?** Your repo may still contain ~534 MB of dependency archives. See [docs/lfs-migration.md](docs/lfs-migration.md) for a one-time cleanup.

## What this repo contains

- `build-local.sh` -- clones upstream source, applies patches, runs the build
- `config/config.local.sh` -- config overlay (ad-hoc signing, optimization flags)
- `patches/` -- fixes for the upstream build scripts
- `.github/workflows/build.yml` -- CI that builds and publishes DMGs

## Credits

All credit to [Moritz Bunkus](https://www.bunkus.org/blog/) and the MKVToolNix contributors for building and maintaining this incredible tool for over 20 years. Moritz provided macOS builds for many years despite not owning a Mac himself -- thank you for that and for all the work that goes into MKVToolNix.

This repo builds on the work of the macOS build community on the [MKVToolNix forum](https://help.mkvtoolnix.download/):

- **[Miklos Juhasz](https://github.com/mjuhasz)** -- contributed macOS patches upstream (dock progress bar, dark/light mode fix in v98.0) and documented key build fixes including the missing include directory and Qt6 build adjustments
- **Ryu67** -- provided community ARM builds (v92 through v98.0) that demonstrated feasibility and kept users going while official builds were unavailable
- **umzyi99** -- documented Qt version-specific fixes and dark mode icon support
- **SoCuul** -- demonstrated signed and notarized builds on Apple Silicon
- **Touchstone64** -- tested v98.0 on macOS 26 and documented dependency URL and Qt compatibility issues

The build patches in this repo were informed by solutions shared across the [Building MKVToolNix with GUI on a Mac](https://help.mkvtoolnix.download/t/building-mkvtoolnix-with-gui-on-a-mac/1361) and [Apple Silicon / Retirement of Rosetta 2](https://help.mkvtoolnix.download/t/apple-silicon-retirement-of-rosetta-2/1371) forum threads.

If you find MKVToolNix useful, consider supporting the project upstream.

Source: https://codeberg.org/mbunkus/mkvtoolnix

License: GPL v2
