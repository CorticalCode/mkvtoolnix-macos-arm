#!/bin/bash
# Backfill SHA256 checksums for existing tarballs and DMGs that don't have one.
# Idempotent: skips any file that already has a matching .sha256.
#
# Scans:
#   ~/opt/proven/{arm,intel}          (the canonical local proven cache)
#   ~/opt/proven-experimental/{arm,intel}
#   <repo>/build                      (internal dev DMGs)
#   <repo>/release                    (release-ready DMGs)
#
# Does NOT scan <repo>/proven/ — those files are LFS-managed and their
# checksums are emitted by build-local.sh during --promote.
#
# Usage: tools/backfill-sha256.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCAN_DIRS=(
  "$HOME/opt/proven/arm"
  "$HOME/opt/proven/intel"
  "$HOME/opt/proven-experimental/arm"
  "$HOME/opt/proven-experimental/intel"
  "$SCRIPT_DIR/build"
  "$SCRIPT_DIR/release"
)

GLOBS=("*.tar.gz" "*.dmg")

generated=0
skipped=0
scanned=0

for dir in "${SCAN_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  echo "Scanning $dir ..."
  for pattern in "${GLOBS[@]}"; do
    for f in "$dir"/$pattern; do
      [[ -f "$f" ]] || continue
      scanned=$((scanned + 1))
      if [[ -f "$f.sha256" ]]; then
        skipped=$((skipped + 1))
        continue
      fi
      filename=$(basename "$f")
      (cd "$(dirname "$f")" && shasum -a 256 "$filename" > "$filename.sha256")
      echo "  generated: $(basename "$f").sha256"
      generated=$((generated + 1))
    done
  done
done

echo ""
echo "Backfill complete."
echo "  Scanned:   $scanned"
echo "  Generated: $generated"
echo "  Skipped:   $skipped (already had .sha256)"
