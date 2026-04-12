# mkvtoolnix-macos-arm

Unofficial macOS Apple Silicon (ARM64) builds of [MKVToolNix](https://mkvtoolnix.download/).

The MKVToolNix developer no longer provides macOS binaries. This repo automates building them from the official source.

## Download

Grab the latest `.dmg` from [Releases](../../releases).

**Note:** The DMG is not signed or notarized. macOS will block it by default.
To open: right-click the app > Open, or run:
```
xattr -cr /Applications/MKVToolNix*.app
```

## Build locally

Requirements: Xcode CLI tools, ~10 GB disk space, 1-3 hours.

```sh
git clone https://github.com/corticalcode/mkvtoolnix-macos-arm.git
cd mkvtoolnix-macos-arm
./build-local.sh release-98.0
```

The DMG will be at `~/tmp/compile/MKVToolNix-98.0.dmg`.

## What this repo contains

- `build-local.sh` -- clones upstream source, applies patches, runs the build
- `config/config.local.sh` -- config overlay (disables code signing)
- `patches/` -- fixes for the upstream build scripts
- `.github/workflows/build.yml` -- CI that builds and publishes DMGs

## Credits

All credit to [Moritz Bunkus](https://www.bunkus.org/blog/) and the MKVToolNix contributors for building and maintaining this incredible tool for over 20 years. Moritz provided macOS builds for many years despite not owning a Mac himself -- thank you for that and for all the work that goes into MKVToolNix.

This repo simply picks up where the official macOS builds left off. If you find MKVToolNix useful, consider supporting the project upstream.

Source: https://codeberg.org/mbunkus/mkvtoolnix

License: GPL v2
