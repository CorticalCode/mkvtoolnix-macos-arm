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
BUILD_MODE="auto"  # auto, full, promote
WORK_DIR=${WORK_DIR:-$HOME/tmp/compile}
TARGET=${TARGET:-$HOME/opt}
PACKAGE_DIR="${TARGET}/packages"
VERIFY_PASSED=false

function usage {
  cat <<'USAGE'
Usage: build-local.sh [options] <tag>

  tag               Upstream release tag (e.g. release-98.0)

Options:
  --full            Force full rebuild from source (proven cache untouched)
  --promote         Archive proven to LFS, replace with current build
  --help            Show this help

Default behavior:
  Wipes workspace, restores dependencies from proven cache,
  builds only what's missing + mkvtoolnix. If no proven cache
  exists, does a full build from source.

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
    --promote)    BUILD_MODE="promote" ;;
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

# Clean ALL stale build directories (not just Qt)
echo "==> Cleaning stale build directories..."
for stale_dir in "${WORK_DIR}"/qt-everywhere-src-* "${WORK_DIR}"/boost_* "${WORK_DIR}"/cmake-* "${WORK_DIR}"/gettext-* "${WORK_DIR}"/gmp-* "${WORK_DIR}"/flac-* "${WORK_DIR}"/libiconv-* "${WORK_DIR}"/libogg-* "${WORK_DIR}"/libvorbis-* "${WORK_DIR}"/zlib-* "${WORK_DIR}"/autoconf-* "${WORK_DIR}"/automake-* "${WORK_DIR}"/pkg-config-* "${WORK_DIR}"/cmark-*; do
  if [[ -d "${stale_dir}" ]]; then
    dir_name="${stale_dir:t}"
    is_expected=false
    for pkg in "${EXPECTED_PACKAGES[@]}"; do
      if [[ "${dir_name}" == "${pkg}"* ]]; then
        is_expected=true
        break
      fi
    done
    if [[ "${is_expected}" == false ]]; then
      echo "    Removing stale: ${dir_name}"
      command rm -rf "${stale_dir}"
    fi
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

function do_promote {
  local proven_dir="${TARGET}/proven"
  local packages_dir="${TARGET}/packages"
  local repo_proven="${SCRIPT_DIR}/proven"

  # Precondition: verification must have passed
  if [[ "${VERIFY_PASSED}" != true ]]; then
    echo "ERROR: Cannot promote — post-build verification did not pass."
    echo "       Build and verify first, then promote."
    exit 1
  fi

  echo "==> Promoting current build to proven cache..."

  # Step 1: Archive current proven to LFS
  if [[ -d "${proven_dir}" ]] && ls "${proven_dir}"/*.tar.gz &>/dev/null; then
    echo "    Archiving current proven to LFS..."
    command cp "${proven_dir}"/*.tar.gz "${repo_proven}/"
    (cd "${SCRIPT_DIR}" && git add proven/*.tar.gz && git commit -m "archive: proven deps before promotion $(date +%Y-%m-%d)")
  fi

  # Step 2: Build new proven set in temp directory
  local proven_new="${TARGET}/proven-new"
  mkdir -p "${proven_new}"
  command cp "${packages_dir}"/*.tar.gz "${proven_new}/"

  # Step 3: Atomic swap
  if [[ -d "${proven_dir}" ]]; then
    command mv "${proven_dir}" "${TARGET}/proven-old"
  fi
  command mv "${proven_new}" "${proven_dir}"

  # Step 4: Cleanup old
  if [[ -d "${TARGET}/proven-old" ]]; then
    command rm -rf "${TARGET}/proven-old"
  fi

  # Step 5: Update LFS with new proven
  command cp "${proven_dir}"/*.tar.gz "${repo_proven}/"
  (cd "${SCRIPT_DIR}" && git add proven/*.tar.gz && git commit -m "promote: proven deps $(date +%Y-%m-%d)")

  echo "==> Promotion complete. Proven cache updated."
  echo "    LFS archive committed. Push when ready."
}

# --- Build ---

cd "${CLONE_DIR}/packaging/macos"

case "${BUILD_MODE}" in
  full)
    echo "==> Full build (all dependencies + mkvtoolnix from source)..."
    wipe_workspace
    ./build.sh
    ;;
  promote)
    if [[ ! -d "${TARGET}/packages" ]] || ! ls "${TARGET}/packages"/*.tar.gz &>/dev/null; then
      echo "ERROR: No build packages found. Build first, then promote."
      exit 1
    fi
    echo "==> Promote mode — skipping build, running verification..."
    ;;
  auto|"")
    wipe_workspace
    if restore_from_proven; then
      echo "==> All dependencies restored from proven. Building mkvtoolnix only..."
      ./build.sh mkvtoolnix
    else
      echo "==> Some dependencies missing from proven. Doing full build..."
      ./build.sh
    fi
    ;;
esac

# Post-build fixups and DMG (skip for promote mode — packages already exist)
if [[ "${BUILD_MODE}" != "promote" ]]; then
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
fi

# --- Post-build verification ---

VERIFY_PASSED=true
DMG_APP="${WORK_DIR}/dmg-${VERSION}/MKVToolNix-${VERSION}.app"

if [[ -d "${DMG_APP}" ]]; then
  echo "==> Running post-build verification..."

  # 1. Qt version in binary
  BUILT_QT_VERSION=$(otool -L "${DMG_APP}/Contents/MacOS/mkvtoolnix-gui" 2>/dev/null | grep libQt6Core | sed 's/.*current version \([0-9.]*\).*/\1/')
  if [[ -n "${BUILT_QT_VERSION}" ]]; then
    if [[ "${BUILT_QT_VERSION}" == "${QTVER}"* ]]; then
      echo "    PASS: Qt version ${BUILT_QT_VERSION} matches expected ${QTVER}"
    else
      echo "    FAIL: Qt version mismatch — binary has ${BUILT_QT_VERSION}, expected ${QTVER}"
      VERIFY_PASSED=false
    fi
  fi

  # 2. Architecture check on ALL binaries and dylibs
  arch_errors=0
  expected_arch="${MACHINE_ARCH}"
  while IFS= read -r -d '' binary; do
    bin_arch=$(file "${binary}" | grep -o 'arm64\|x86_64')
    if [[ "${bin_arch}" != "${expected_arch}" ]]; then
      echo "    FAIL: Wrong architecture in ${binary:t}: ${bin_arch} (expected ${expected_arch})"
      arch_errors=$((arch_errors + 1))
      VERIFY_PASSED=false
    fi
  done < <(find "${DMG_APP}/Contents/MacOS" \( -name "*.dylib" -o -type f -perm +111 \) -not -type d -print0 2>/dev/null)
  if [[ ${arch_errors} -eq 0 ]]; then
    echo "    PASS: All binaries and dylibs are ${expected_arch}"
  fi

  # 3. Duplicate dylib scan
  dupes=$(find "${DMG_APP}/Contents/MacOS/libs" -name "*.dylib" -not -type l 2>/dev/null | sed 's/\.[0-9]*\.[0-9]*\.[0-9]*\.dylib/.dylib/' | sort | uniq -d)
  if [[ -n "${dupes}" ]]; then
    echo "    FAIL: Duplicate dylib versions found:"
    echo "${dupes}" | while read -r d; do echo "      ${d}"; done
    VERIFY_PASSED=false
  else
    echo "    PASS: No duplicate dylib versions"
  fi

  # 4. Size sanity check
  app_size=$(du -sk "${DMG_APP}" 2>/dev/null | awk '{print $1}')
  size_mb=$((app_size / 1024))
  min_size=70  # MB — below this something is missing
  max_size=95  # MB — above this something is duplicated
  if [[ ${size_mb} -lt ${min_size} ]]; then
    echo "    FAIL: App is ${size_mb} MB — suspiciously small (expected ${min_size}-${max_size} MB)"
    VERIFY_PASSED=false
  elif [[ ${size_mb} -gt ${max_size} ]]; then
    echo "    FAIL: App is ${size_mb} MB — suspiciously large (expected ${min_size}-${max_size} MB)"
    VERIFY_PASSED=false
  else
    echo "    PASS: App size ${size_mb} MB (expected range ${min_size}-${max_size} MB)"
  fi

  # 5. Bundle inventory
  echo "    --- Bundle inventory ---"
  find "${DMG_APP}/Contents/MacOS/libs" -name "*.dylib" -not -type l 2>/dev/null | while read -r lib; do
    echo "    $(basename "${lib}")"
  done

  # Summary
  if [[ "${VERIFY_PASSED}" == true ]]; then
    echo "==> Verification: ALL CHECKS PASSED"
  else
    echo "==> Verification: SOME CHECKS FAILED — review output above"
  fi
else
  echo "==> WARNING: App bundle not found at ${DMG_APP} — skipping verification"
  VERIFY_PASSED=false
fi

# Handle promotion after verification
if [[ "${BUILD_MODE}" == "promote" ]]; then
  do_promote
  exit 0
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
