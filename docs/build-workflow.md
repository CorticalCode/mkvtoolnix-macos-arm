# Build Workflow

## Quick Reference

| Flag | Purpose | Who | Build time | Requires |
|------|---------|-----|-----------|----------|
| *(default)* | Auto-detect: use cache if available, otherwise full build | Anyone | 15 min (cached) / 1-3 hrs (full) | Tag |
| `--restore-cache` | Pull pre-built deps from LFS to local cache | Anyone | ~2 min | Tag |
| `--full` | Rebuild all dependencies from source | Anyone | 1-3 hours | Tag |
| `--promote` | Archive verified build to LFS | Maintainer | ~1 min | Verified build |

## First-Time Setup

Choose your path based on whether you want to use pre-built dependencies or compile everything yourself.

```mermaid
flowchart TD
    A["<b>git clone</b> repo<br/><i>~1 MB, no binaries</i>"] --> B{"Want pre-built<br/>dependencies?"}

    B -->|Yes| C["<b>--restore-cache</b><br/>Pull from Git LFS"]
    C --> D["Local cache populated<br/><i>~/opt/proven/{arch}/</i>"]
    D --> E["<b>./build-local.sh</b> tag<br/><i>~15 min</i>"]

    B -->|No| F["<b>./build-local.sh</b> tag<br/><i>~1-3 hours</i>"]

    E --> G["DMG ready"]
    F --> G

    style A fill:#e8f4fd,stroke:#2196f3
    style C fill:#e8f5e9,stroke:#4caf50
    style G fill:#fff3e0,stroke:#ff9800
```

## Build Mode Decision Tree

What happens inside the build script depending on the flag you pass.

```mermaid
flowchart TD
    START["./build-local.sh [flag] tag"] --> MODE{Flag?}

    MODE -->|--restore-cache| RC1["Pull LFS for current arch"]
    RC1 --> RC2["Copy to ~/opt/proven/{arch}/"]
    RC2 --> RC3["Verify all packages arrived"]
    RC3 --> RC4["Clean up repo LFS objects"]
    RC4 --> RC5(("Exit<br/><i>cache ready</i>"))

    MODE -->|--full| F1["Wipe workspace"]
    F1 --> F2["Build ALL deps from source"]
    F2 --> POST

    MODE -->|default / auto| A1["Wipe workspace"]
    A1 --> A2{"~/opt/proven/{arch}/<br/>has all packages?"}
    A2 -->|Yes| A3["Restore deps from cache"]
    A3 --> A4["Build mkvtoolnix only"]
    A4 --> POST
    A2 -->|No| A5["Build ALL deps from source"]
    A5 --> POST

    MODE -->|--promote| P1{"Previous build<br/>verified?"}
    P1 -->|No| P2(("Error<br/><i>build first</i>"))
    P1 -->|Yes| P3["Archive current proven to LFS"]
    P3 --> P4["Swap local cache with new packages"]
    P4 --> P5["Commit new proven to LFS"]
    P5 --> P6["Clean up repo LFS objects"]
    P6 --> P7(("Exit<br/><i>push when ready</i>"))

    POST["Post-build verification"] --> DMG["Package DMG"]
    DMG --> DONE(("Done<br/><i>DMG ready</i>"))

    style RC5 fill:#e8f5e9,stroke:#4caf50
    style P2 fill:#ffebee,stroke:#f44336
    style P7 fill:#e8f5e9,stroke:#4caf50
    style DONE fill:#fff3e0,stroke:#ff9800
```

## Dependency Lifecycle

How dependencies flow between Git LFS, the local cache, and the build system.

```mermaid
flowchart LR
    LFS["<b>Git LFS</b><br/><i>proven/{arch}/</i><br/>Archival storage"]
    LC["<b>Local Cache</b><br/><i>~/opt/proven/{arch}/</i><br/>Build-time restore"]
    PKG["<b>Packages</b><br/><i>~/opt/packages/</i><br/>Build output"]

    LFS -- "--restore-cache" --> LC
    LC -- "auto mode<br/>restore" --> BUILD(("Build"))
    BUILD -- "produces" --> PKG
    PKG -- "--promote<br/>(maintainer)" --> LFS

    FULL["--full"] -. "bypasses" .-> LC
    FULL --> BUILD

    style LFS fill:#e8f4fd,stroke:#2196f3
    style LC fill:#e8f5e9,stroke:#4caf50
    style PKG fill:#fff3e0,stroke:#ff9800
    style BUILD fill:#f3e5f5,stroke:#9c27b0
```

> **Key insight:** `--restore-cache` and `--promote` are two ends of the same loop. Dependencies are pulled from LFS into the local cache, used during builds, and (for maintainers) promoted back to LFS after verification. The `--full` flag bypasses the cache entirely, building everything from source.

## Common Workflows

### Update documentation (no build needed)

```sh
git clone https://github.com/CorticalCode/mkvtoolnix-gui-macos.git
cd mkvtoolnix-gui-macos
# Edit docs, commit, push — no LFS objects downloaded
```

### First build on a new machine (fast path)

```sh
git clone https://github.com/CorticalCode/mkvtoolnix-gui-macos.git
cd mkvtoolnix-gui-macos
./build-local.sh --restore-cache          # ~2 min, populates local cache
./build-local.sh release-98.0             # ~15 min, uses cached deps
```

### First build on a new machine (from source)

```sh
git clone https://github.com/CorticalCode/mkvtoolnix-gui-macos.git
cd mkvtoolnix-gui-macos
./build-local.sh release-98.0             # ~1-3 hours, builds everything
```

### Subsequent builds (cache already populated)

```sh
./build-local.sh release-98.0             # ~15 min, auto-restores from cache
```

### Promote after verified build (maintainer only)

```sh
./build-local.sh --full release-98.0      # Full rebuild from source
./build-local.sh --promote release-98.0   # Archive to LFS, clean up
git push                                  # Share with others
```
