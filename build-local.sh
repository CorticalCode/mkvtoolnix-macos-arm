#!/bin/zsh
set -e

SCRIPT_DIR=${0:a:h}
UPSTREAM_URL="https://codeberg.org/mbunkus/mkvtoolnix.git"

# Detect architecture
MACHINE_ARCH=$(uname -m)
if [[ "${MACHINE_ARCH}" == "arm64" ]]; then
  ARCH_LABEL="arm"
elif [[ "${MACHINE_ARCH}" == "x86_64" ]]; then
  ARCH_LABEL="intel"
else
  ARCH_LABEL="${MACHINE_ARCH}"
fi

function wipe_workspace {
  echo "==> Wiping workspace (preserving proven/ and source/)..."

  # Preserve list — everything else under TARGET gets removed
  local preserve_proven="${TARGET}/proven"
  local preserve_source="${TARGET}/source"

  for item in "${TARGET}"/*; do
    [[ "${item}" == "${preserve_proven}" ]] && continue
    [[ "${item}" == "${preserve_source}" ]] && continue
    echo "    Removing ${item:t}/"
    command rm -rf "${item}"
  done

  # Recreate essential directories
  mkdir -p "${TARGET}/include" "${TARGET}/lib" "${TARGET}/bin" "${TARGET}/packages"
  echo "==> Workspace clean."
}

# Defaults
TAG=""
BUILD_MODE="auto"  # auto, full, skip-deps, only
BUILD_TARGETS=()
WORK_DIR=${WORK_DIR:-$HOME/tmp/compile}
TARGET=${TARGET:-$HOME/opt}
PACKAGE_DIR="${TARGET}/packages"

function usage {
  cat <<'USAGE'
Usage: build-local.sh [options] <tag>

  tag               Upstream release tag (e.g. release-98.0)

Options:
  --full            Force full rebuild of all dependencies + mkvtoolnix
  --skip-deps       Restore cached deps, only build mkvtoolnix
  --only <targets>  Build only specific targets (e.g. --only qt mkvtoolnix)
  --help            Show this help

Default behavior (auto):
  If all dependency packages are cached in ~/opt/packages/,
  restores them and only builds mkvtoolnix. Otherwise does a full build.

Environment:
  WORK_DIR          Compile workspace (default: ~/tmp/compile)
  TARGET            Install prefix (default: ~/opt)
USAGE
  exit 0
}

# Parse arguments
while [[ -n $1 ]]; do
  case $1 in
    --full)       BUILD_MODE="full" ;;
    --skip-deps)  BUILD_MODE="skip-deps" ;;
    --only)       BUILD_MODE="only"; shift
                  while [[ -n $1 ]] && [[ $1 != --* ]]; do
                    BUILD_TARGETS+=("$1"); shift
                  done; continue ;;
    --help|-h)    usage ;;
    -*)           echo "Unknown option: $1"; usage ;;
    *)            TAG="$1" ;;
  esac
  shift
done

if [[ -z "${TAG}" ]]; then
  TAG="release-98.0"
fi
VERSION=${TAG#release-}

echo "==> Building MKVToolNix ${VERSION} for ${MACHINE_ARCH} (${ARCH_LABEL})"
echo "==> Mode: ${BUILD_MODE}"
echo "==> Work directory: ${WORK_DIR}"

# Ensure required directories exist
mkdir -p "${TARGET}/include" "${TARGET}/lib" "${PACKAGE_DIR}" "${WORK_DIR}"

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
command cp "${SCRIPT_DIR}/config/config.local.sh" "${CLONE_DIR}/packaging/macos/config.local.sh"

# Reset source tree and apply patches fresh
echo "==> Applying patches..."
cd "${CLONE_DIR}"
git checkout -- .
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
  [[ -f "${patch}" ]] || continue
  echo "    Applying ${patch:t}..."
  git apply --check "${patch}" 2>/dev/null && git apply "${patch}" || echo "    (already applied or skipped)"
done

# Copy Qt source patches (applied by upstream build.sh via qt-patches/ mechanism)
if [[ -d "${SCRIPT_DIR}/patches/qt-patches" ]]; then
  echo "==> Installing Qt source patches..."
  command cp -r "${SCRIPT_DIR}/patches/qt-patches" "${CLONE_DIR}/packaging/macos/qt-patches"
fi

# --- Pre-build verification ---

# Source the config files the same way build.sh does, to get QTVER
source "${CLONE_DIR}/packaging/macos/config.sh"
test -f "${CLONE_DIR}/packaging/macos/config.local.sh" && source "${CLONE_DIR}/packaging/macos/config.local.sh"
source "${CLONE_DIR}/packaging/macos/specs.sh"

# Verify QTVER matches what specs.sh will download
SPECS_QT_FILE="${spec_qt[1]}"
EXPECTED_QT_DIR="qt-everywhere-src-${QTVER}"
if [[ "${SPECS_QT_FILE}" != "${EXPECTED_QT_DIR}.tar.xz" ]]; then
  echo "ERROR: Qt version mismatch!"
  echo "  QTVER=${QTVER} expects: ${EXPECTED_QT_DIR}.tar.xz"
  echo "  specs.sh has: ${SPECS_QT_FILE}"
  echo "  Fix: update QTVER in config/config.local.sh to match specs-updates.patch"
  exit 1
fi
echo "==> Verified: QTVER=${QTVER} matches specs.sh (${SPECS_QT_FILE})"

# Clean stale Qt build directories to prevent version masking
# Only the directory matching QTVER should exist after extraction
for stale_qt in "${WORK_DIR}"/qt-everywhere-src-*; do
  if [[ -d "${stale_qt}" ]] && [[ "${stale_qt}" != "${WORK_DIR}/${EXPECTED_QT_DIR}" ]]; then
    echo "==> Removing stale Qt directory: ${stale_qt:t}"
    rm -rf "${stale_qt}"
  fi
done

# --- Dependency caching logic ---

# All deps that the full build produces (excluding docbook_xsl which self-caches)
EXPECTED_PACKAGES=(
  autoconf-2.69
  automake-1.16.1
  pkg-config-0.29.2
  libiconv-1.16
  cmake-3.31.3
  libogg-1.3.4
  libvorbis-1.3.7
  flac-1.5.0
  zlib-1.3.1
  gettext-0.23
  cmark-0.30.3
  gmp-6.3.0
  boost_1_88_0
  qt-everywhere-src-6.10.2
)

function check_deps_cached {
  for pkg in "${EXPECTED_PACKAGES[@]}"; do
    if [[ ! -f "${PACKAGE_DIR}/${pkg}.tar.gz" ]]; then
      echo "    Missing: ${pkg}"
      return 1
    fi
  done
  return 0
}

function restore_from_proven {
  local proven_dir="${TARGET}/proven"
  local restored=0
  local missing=()

  echo "==> Restoring from proven cache..."

  for pkg in "${EXPECTED_PACKAGES[@]}"; do
    local pkg_file="${proven_dir}/${pkg}.tar.gz"
    if [[ -f "${pkg_file}" ]]; then
      echo "    Restoring ${pkg}..."
      (cd "${TARGET}" && tar xzf "${pkg_file}")
      ((restored++))
    else
      echo "    Missing from proven: ${pkg}"
      missing+=("${pkg}")
    fi
  done

  # Restore docbook-xsl if archived
  local docbook_archive="${proven_dir}/docbook-xsl.tar.gz"
  if [[ -f "${docbook_archive}" ]]; then
    echo "    Restoring docbook-xsl..."
    (cd "${TARGET}" && tar xzf "${docbook_archive}")
    ((restored++))
  else
    echo "    Missing from proven: docbook-xsl"
    missing+=("docbook-xsl")
  fi

  echo "==> Restored ${restored} packages. Missing: ${#missing[@]}."

  if [[ ${#missing[@]} -gt 0 ]]; then
    return 1
  fi
  return 0
}

# Auto-detect mode: check if deps are cached
if [[ "${BUILD_MODE}" == "auto" ]]; then
  echo "==> Checking for cached dependencies..."
  if check_deps_cached; then
    echo "==> All dependencies cached. Skipping dep builds."
    BUILD_MODE="skip-deps"
  else
    echo "==> Some dependencies missing. Doing full build."
    BUILD_MODE="full"
  fi
fi

# --- Build ---

cd "${CLONE_DIR}/packaging/macos"

case "${BUILD_MODE}" in
  full)
    echo "==> Full build (all dependencies + mkvtoolnix)..."
    ./build.sh
    ;;
  skip-deps)
    restore_deps
    echo "==> Building mkvtoolnix only..."
    ./build.sh mkvtoolnix
    ;;
  only)
    if [[ ${#BUILD_TARGETS[@]} -eq 0 ]]; then
      echo "Error: --only requires at least one target"
      exit 1
    fi
    # Restore deps first so build targets have their dependencies available
    if check_deps_cached; then
      restore_deps
    fi
    echo "==> Building: ${BUILD_TARGETS[*]}..."
    ./build.sh "${BUILD_TARGETS[@]}"
    ;;
esac

# Rename unversioned cmark package to include version
if [[ -f "${TARGET}/packages/mtx-build.tar.gz" ]]; then
  cmark_version=$(echo "${EXPECTED_PACKAGES[@]}" | tr ' ' '\n' | grep "^cmark-")
  if [[ -n "${cmark_version}" ]]; then
    echo "==> Renaming mtx-build.tar.gz to ${cmark_version}.tar.gz"
    command mv "${TARGET}/packages/mtx-build.tar.gz" "${TARGET}/packages/${cmark_version}.tar.gz"
  fi
fi

# Archive docbook-xsl if not already in packages
if [[ -d "${TARGET}/xsl-stylesheets" ]] && [[ ! -f "${TARGET}/packages/docbook-xsl.tar.gz" ]]; then
  echo "==> Archiving docbook-xsl..."
  (cd "${TARGET}" && tar czf "${TARGET}/packages/docbook-xsl.tar.gz" xsl-stylesheets docbook-xsl-*)
fi

# Package DMG
echo "==> Building DMG..."
./build.sh dmg

# --- Post-build verification ---

DMG_APP="${WORK_DIR}/dmg-${VERSION}/MKVToolNix-${VERSION}.app"
if [[ -d "${DMG_APP}" ]]; then
  # Verify Qt version in the built binary
  BUILT_QT_VERSION=$(otool -L "${DMG_APP}/Contents/MacOS/mkvtoolnix-gui" 2>/dev/null | grep libQt6Core | sed 's/.*current version \([0-9.]*\).*/\1/')
  if [[ -n "${BUILT_QT_VERSION}" ]]; then
    if [[ "${BUILT_QT_VERSION}" == "${QTVER}"* ]]; then
      echo "==> Verified: built binary links Qt ${BUILT_QT_VERSION} (expected ${QTVER})"
    else
      echo "WARNING: Qt version mismatch in built binary!"
      echo "  Expected: ${QTVER}"
      echo "  Got: ${BUILT_QT_VERSION}"
      echo "  The build may have used a stale Qt directory."
    fi
  fi

  # Verify architecture
  BUILT_ARCH=$(file "${DMG_APP}/Contents/MacOS/mkvtoolnix-gui" | grep -o 'arm64\|x86_64')
  echo "==> Verified: binary architecture is ${BUILT_ARCH}"
fi

# --- Name and copy DMG to dist/ ---

DIST_DIR="${SCRIPT_DIR}/dist"
BUILD_COUNTER_FILE="${SCRIPT_DIR}/.build-counter-${ARCH_LABEL}"
mkdir -p "${DIST_DIR}"

DMG_PATH="${WORK_DIR}/MKVToolNix-${VERSION}.dmg"

if [[ -f "${DMG_PATH}" ]]; then
  # Increment global build counter
  if [[ -f "${BUILD_COUNTER_FILE}" ]]; then
    BUILD_NUM=$(( $(cat "${BUILD_COUNTER_FILE}") + 1 ))
  else
    BUILD_NUM=1
  fi
  echo "${BUILD_NUM}" > "${BUILD_COUNTER_FILE}"

  # Get current git branch name for the label
  BRANCH=$(cd "${SCRIPT_DIR}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

  DMG_NAME="MKVToolNix-${VERSION}-macos-${ARCH_LABEL}-${BRANCH}-b$(printf '%03d' ${BUILD_NUM}).dmg"
  command cp "${DMG_PATH}" "${DIST_DIR}/${DMG_NAME}"
  echo "==> Done!"
  echo "    Build output: ${DMG_PATH}"
  echo "    Distribution: ${DIST_DIR}/${DMG_NAME}"
else
  echo "==> DMG not found at expected path. Check ${WORK_DIR} for output."
  ls -la "${WORK_DIR}"/MKVToolNix*.dmg 2>/dev/null || true
fi
