# Contributing to mkvtoolnix-gui-macos

This is a thin wrapper repo. The actual MKVToolNix source lives upstream
at [codeberg.org/mbunkus/mkvtoolnix](https://codeberg.org/mbunkus/mkvtoolnix). This repo
contains build patches, config overlays, the wrapper script, and CI.

## Local hook setup (one-time)

After cloning, activate the repo's git hooks:

```sh
git config core.hooksPath .githooks
```

## Patches

- Patches live in `patches/` and apply against the upstream source
  cloned at the build's tagged release. See `PATCHES.md` for what
  each patch does and why.
- Generate patches from `git diff` against the pristine upstream
  tree, not from the patched working state.
- Verify with `git apply --check patches/foo.patch` before committing.
- Document root cause in `PATCHES.md` for any new active patch.

## Build verification

Every build verifies the upstream `mkvtoolnix-${VERSION}.tar.xz`
against an OpenPGP signature published by Moritz Bunkus before
running. See `docs/tarball-verification.md` for the threat model
and operational details.

## Commit messages

- `type: description` form (`fix`, `feat`, `perf`, `docs`, `chore`).
- Co-author trailers for AI-assisted commits.
- See recent `git log` for examples.

## Pushing

The maintainer pushes manually and reviews each push. PRs against
the public repo on GitHub are welcome but please open an issue first
to discuss anything beyond a one-line fix.
