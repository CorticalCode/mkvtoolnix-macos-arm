# Proven Dependency Cache

The build system caches compiled dependencies so that subsequent builds only need to rebuild MKVToolNix itself (~15 minutes instead of 1-3 hours).

## How it works

When you run `./build-local.sh release-98.0`:

1. The workspace (`~/opt/`) is wiped clean (except the cache and source tarballs)
2. Compiled dependencies are restored from `~/opt/proven/{arch}/`
3. If all 15 dependencies are found, only MKVToolNix is built from source
4. If any are missing, a full build from source runs automatically

The cache is per-architecture — Apple Silicon (arm64) and Intel (x86_64) have separate caches and cannot cross-contaminate.

## Populating the cache

After a successful build and manual testing:

```sh
./build-local.sh release-98.0 --promote
```

This runs post-build verification (Qt version, architecture, duplicate libraries, app size), then copies the compiled packages to the proven cache. If verification fails, promotion is blocked.

## What's in the cache

15 files per architecture — one `.tar.gz` per dependency:

| Package | Description |
|---------|-------------|
| autoconf, automake, pkg-config | Build tools |
| cmake | Build system (bootstrapped from source) |
| libiconv, gettext | Internationalization |
| libogg, libvorbis, flac | Audio codecs |
| zlib | Compression |
| cmark | CommonMark parser (used by GUI) |
| gmp | Arbitrary precision math |
| boost | C++ libraries |
| qt-everywhere-src | Qt 6 framework |
| docbook-xsl | Documentation stylesheets |

## Restoring from Git LFS

The proven cache is archived in the repository via Git LFS under `proven/{arch}/`. On a new machine:

```sh
git clone https://github.com/CorticalCode/mkvtoolnix-gui-macos.git
cd mkvtoolnix-gui-macos
git lfs pull

# Copy the cached deps for your architecture
mkdir -p ~/opt/proven
cp -r proven/arm ~/opt/proven/    # Apple Silicon
# or
cp -r proven/intel ~/opt/proven/  # Intel

# Build (will restore from cache, ~15 minutes)
./build-local.sh release-98.0
```

## Forcing a full rebuild

To rebuild all dependencies from source (ignoring the cache):

```sh
./build-local.sh release-98.0 --full
```

The proven cache is not modified by `--full` — it remains as a safety net.

## Invalidating a single dependency

If you modify a patch that affects a specific dependency without bumping its version, delete that package from the cache to force a rebuild:

```sh
rm ~/opt/proven/arm/qt-everywhere-src-6.10.2.tar.gz
./build-local.sh release-98.0  # will detect missing Qt and do a full build
```
