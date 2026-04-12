#!/bin/zsh
set -e

SCRIPT_DIR=${0:a:h}
TAG=${1:-release-98.0}
VERSION=${TAG#release-}
WORK_DIR=${WORK_DIR:-$HOME/tmp/compile}
UPSTREAM_URL="https://codeberg.org/mbunkus/mkvtoolnix.git"

echo "==> Building MKVToolNix ${VERSION} for ARM64"
echo "==> Work directory: ${WORK_DIR}"

# Ensure required directories exist
mkdir -p "$HOME/opt/include" "$HOME/opt/lib" "${WORK_DIR}"

# Clone upstream at the specified tag
CLONE_DIR="${WORK_DIR}/mkvtoolnix-src"
if [[ ! -d "${CLONE_DIR}/.git" ]]; then
  echo "==> Cloning upstream ${TAG}..."
  git clone --depth 1 --branch "${TAG}" "${UPSTREAM_URL}" "${CLONE_DIR}"
else
  echo "==> Source already cloned at ${CLONE_DIR}"
  echo "    To re-clone, remove it: rm -rf ${CLONE_DIR}"
fi

# Copy our config overlay
echo "==> Applying config overlay..."
cp "${SCRIPT_DIR}/config/config.local.sh" "${CLONE_DIR}/packaging/macos/config.local.sh"

# Apply patches
echo "==> Applying patches..."
cd "${CLONE_DIR}"
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
  [[ -f "${patch}" ]] || continue
  echo "    Applying ${patch:t}..."
  git apply --check "${patch}" 2>/dev/null && git apply "${patch}" || echo "    (already applied or skipped)"
done

# Build
echo "==> Running build.sh (this will take a while)..."
cd "${CLONE_DIR}/packaging/macos"
./build.sh

# Package DMG
echo "==> Building DMG..."
./build.sh dmg

DMG_PATH="${WORK_DIR}/MKVToolNix-${VERSION}.dmg"
if [[ -f "${DMG_PATH}" ]]; then
  echo "==> Done! DMG at: ${DMG_PATH}"
else
  echo "==> DMG not found at expected path. Check ${WORK_DIR} for output."
  ls -la "${WORK_DIR}"/MKVToolNix*.dmg 2>/dev/null || true
fi
