# Upstream Tarball Verification

Every build verifies the upstream `mkvtoolnix-${VERSION}.tar.xz` source tarball
against an OpenPGP signature published by the upstream maintainer
([Moritz Bunkus](https://www.bunkus.org/)) before invoking the build script.
This guide explains what it does, why it exists, and how to operate it.

## Why this exists

Upstream's `packaging/macos/build.sh` does **not** checksum or verify the
mkvtoolnix tarball — `build_package /literal-path` mode bypasses
`retrieve_file`, so unlike Qt, Boost, FLAC, etc., the tarball is taken
on faith. If the file at `~/opt/source/mkvtoolnix-${VERSION}.tar.xz` is
silently replaced (server compromise, accidental local overwrite, a
buggy helper script), the next build picks it up with no detection.

That gap is exactly what enabled an internal contamination incident
in April 2026: an experimental source tree was staged into the
official tarball slot, the next "production" build silently used it,
and the resulting DMG contained patched experimental code presented
as a clean release.

## Threat model

```mermaid
flowchart LR
    A["Attacker /<br/>accident"] -->|"replaces tarball<br/>locally"| T["~/opt/source/<br/>mkvtoolnix-X.tar.xz"]
    A -->|"compromises<br/>download server"| S["mkvtoolnix.download/<br/>sources/"]
    T --> B["build-local.sh"]
    S -->|"on first download"| T
    B --> D["DMG"]

    style A fill:#ffebee,stroke:#c62828
    style T fill:#fff3e0,stroke:#ff9800
    style S fill:#fff3e0,stroke:#ff9800
    style B fill:#e8f5e9,stroke:#4caf50
    style D fill:#e3f2fd,stroke:#2196f3
```

| Threat | SHA256 from same server | OpenPGP signature |
|---|---|---|
| Network corruption / partial download | Caught | Caught |
| Local file replacement | Caught | Caught |
| `mkvtoolnix.download` server compromised | **Bypassed** — attacker also serves matching SHA | **Caught** — attacker can't forge a valid signature without the private key |
| Confirms identity of who released it | No | Yes |

OpenPGP gives strictly more protection than SHA256 alone, so we use it.

## Trust artifacts

Three files in this repo make the verification work:

```mermaid
flowchart LR
    K["tools/<br/>mbunkus-pubkey.asc<br/><i>10 KB embedded key</i>"]
    F["tools/<br/>mbunkus-fingerprint.txt<br/><i>40-hex pinned FP</i>"]
    R["tools/<br/>README.md<br/><i>provenance docs</i>"]
    W[".github/workflows/<br/>verify-mbunkus-key.yml<br/><i>monthly drift action</i>"]

    K -.->|"primary FP must match"| F
    R -.->|"documents both"| K
    R -.->|"documents both"| F
    W -.->|"re-checks against<br/>3 sources monthly"| F

    style K fill:#e8f4fd,stroke:#2196f3
    style F fill:#fff3e0,stroke:#ff9800
    style R fill:#f3e5f5,stroke:#9c27b0
    style W fill:#e8f5e9,stroke:#4caf50
```

- **`tools/mbunkus-pubkey.asc`** — Moritz Bunkus's full public key,
  fetched from `https://bunkus.org/gpg-pub-moritzbunkus.txt` on
  2026-04-25. Public keys are designed for redistribution; this is
  exactly the use case mbunkus published the key for.
- **`tools/mbunkus-fingerprint.txt`** — primary key fingerprint
  (`D9199745B0545F2E8197062B0F92290A445B9007`) pinned in plain text.
  Build script verifies the embedded `.asc` primary FP matches this
  before trusting it. Tampering with one without the other shows up
  as two suspicious diffs in review.
- **`.github/workflows/verify-mbunkus-key.yml`** — re-checks the
  pinned fingerprint against three independent sources monthly.
  Fails (and emails the maintainer) on any drift.

## How a build verifies the tarball

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant W as build-local.sh
    participant FS as ~/opt/source/
    participant UP as mkvtoolnix.download
    participant G as gpg (temp keyring)

    U->>W: ./build-local.sh release-98.0
    W->>W: Cross-check pubkey FP vs<br/>pinned fingerprint
    alt FP mismatch
        W-->>U: ERROR — refuse to build
    end

    W->>FS: tarball exists?
    alt tarball missing
        W->>UP: GET mkvtoolnix-98.0.tar.xz
        UP-->>FS: tarball
    end
    W->>FS: .sig exists?
    alt .sig missing
        W->>UP: GET mkvtoolnix-98.0.tar.xz.sig
        UP-->>FS: signature
    end

    W->>G: import embedded pubkey<br/>(temp keyring, isolated)
    W->>G: verify .sig against tarball

    alt signature valid
        G-->>W: exit 0
        W->>U: proceed to build
    else signature invalid
        G-->>W: exit 1
        W-->>U: ERROR + remediation steps<br/>(no build)
    end
```

The temp keyring is isolated from the user's main keyring — the build
verification doesn't depend on what you have in `~/.gnupg/`, and
doesn't pollute it.

## Drift detection (monthly action)

```mermaid
sequenceDiagram
    autonumber
    participant CR as Cron (1st of month)
    participant A as verify-mbunkus-key action
    participant B as bunkus.org
    participant C as Codeberg
    participant K as keys.openpgp.org
    participant M as Maintainer

    CR->>A: trigger
    A->>A: read pinned FP

    par parallel fetch
        A->>B: GET pub key
        B-->>A: key bytes
        A->>A: extract primary FP
    and
        A->>C: GET pub key
        C-->>A: key bytes
        A->>A: extract primary FP
    and
        A->>K: GET pub key by FP
        K-->>A: key bytes
        A->>A: extract primary FP
    end

    alt all 3 sources reachable AND match pinned
        A->>M: pass (silent)
    else any source disagrees
        A->>M: fail + email notification
        Note over M: human reviews,<br/>opens PR if drift is real
    end
```

The action **never auto-updates**. Drift signals require a human PR
that updates `tools/mbunkus-pubkey.asc` and (if the primary key
changed) `tools/mbunkus-fingerprint.txt`, with provenance noted in
the commit message.

## What to do if verification fails

```mermaid
flowchart TD
    Start[Build fails with<br/>'GPG signature verification FAILED']
    Start --> Q1{Did you copy<br/>or modify the tarball<br/>recently?}

    Q1 -->|Yes| Fix1[rm ~/opt/source/mkvtoolnix-X.tar.xz<br/>rm ~/opt/source/mkvtoolnix-X.tar.xz.sig<br/>rerun build]
    Q1 -->|No| Q2{Has the monthly<br/>workflow alerted<br/>about key drift?}

    Q2 -->|Yes| Refresh[Refresh tools/mbunkus-pubkey.asc<br/>per tools/README.md]
    Q2 -->|No| Q3{Can you reach<br/>mkvtoolnix.download<br/>at all?}

    Q3 -->|No| Wait[Wait — server may be down.<br/>Check status, retry later]
    Q3 -->|Yes| Manual[Run gpg verify by hand:<br/>gpg --verify .sig file<br/>read the actual error]

    Fix1 --> Done[Build succeeds]
    Refresh --> Done
    Manual --> Investigate[Investigate root cause<br/>before deleting anything]

    style Start fill:#ffebee,stroke:#c62828
    style Done fill:#e8f5e9,stroke:#4caf50
    style Investigate fill:#fff3e0,stroke:#ff9800
```

The script always hard-fails and reports; it never auto-deletes the
tarball or attempts a "self-heal" re-download on failure. The
decision to delete and re-download is yours, after you've understood
why verification failed.

## Refreshing the embedded key

If the monthly workflow fails or mbunkus rotates a subkey:

1. Re-fetch from at least two independent sources, confirm primary
   fingerprint still matches `tools/mbunkus-fingerprint.txt`:
   ```sh
   curl -fsSL https://bunkus.org/gpg-pub-moritzbunkus.txt | gpg --show-keys --with-colons | awk -F: '$1=="fpr" {print $10; exit}'
   curl -fsSL https://codeberg.org/mbunkus.gpg | gpg --show-keys --with-colons | awk -F: '$1=="fpr" {print $10; exit}'
   ```
2. If primary FP unchanged: replace `tools/mbunkus-pubkey.asc` with
   the new fetch from bunkus.org.
3. Verify locally:
   ```sh
   ./build-local.sh release-XX.X  # pre-flight will exercise the new key
   ```
4. Commit with provenance note in the message.

If the **primary fingerprint itself changes**, that's a key rotation
event:
- Verify the new fingerprint via at least two out-of-band channels
  (freshly fetched bunkus.org page, signed announcement, in-person
  if possible)
- Update both `tools/mbunkus-fingerprint.txt` AND `tools/mbunkus-pubkey.asc`
- Document the rotation date and verification path in the commit
  message and in `tools/README.md`'s provenance section

## Local trust convenience

The build script's verification works regardless of what's in your
personal `~/.gnupg/`. But manual `gpg --verify` from your shell will
print a "WARNING: This key is not certified with a trusted signature"
line until you locally sign the key. To silence it:

```sh
gpg --import tools/mbunkus-pubkey.asc        # import to your keyring
gpg --lsign-key D9199745B0545F2E8197062B0F92290A445B9007
```

This adds a non-exportable local signature meaning "I personally
verified this is mbunkus." After that, `gpg --verify` shows
`[full]` instead of `[unknown]`, no warning. Owner-trust adjustment
is unnecessary for our use case (web-of-trust propagation isn't
relevant here).

## Verification chain summary

```mermaid
flowchart LR
    K1["bunkus.org<br/>pub key"]
    K2["Codeberg<br/>pub key"]
    K3["keys.openpgp.org<br/>pub key by FP"]
    K4["keyserver.ubuntu.com<br/>pub key"]

    K1 -->|FP| FP["pinned FP<br/>D9199745...445B9007"]
    K2 -->|FP| FP
    K3 -->|FP| FP
    K4 -->|FP| FP

    FP -->|matches embedded key| EK["tools/<br/>mbunkus-pubkey.asc"]
    EK -->|imported to temp keyring| TG["gpg verify<br/>tarball + .sig"]
    TG -->|exit 0| OK["build proceeds"]

    style FP fill:#fff3e0,stroke:#ff9800
    style EK fill:#e8f4fd,stroke:#2196f3
    style OK fill:#e8f5e9,stroke:#4caf50
```

Four independent channels published the same primary fingerprint on
2026-04-25. The pinned FP is the consensus value. The embedded key
must match the pinned FP. The tarball must verify against the
embedded key's signing subkey. Any link in the chain breaking
hard-fails the build.
