#!/bin/zsh
# Guard: must be executed by zsh, not sourced or run by another shell
if [[ -z "${ZSH_VERSION}" ]]; then
  echo "ERROR: This script requires zsh. Run it with: ./build-local.sh" >&2
  exit 1
fi
if [[ "${ZSH_EVAL_CONTEXT}" == *:file ]]; then
  echo "ERROR: This script must be executed, not sourced." >&2
  return 1
fi

set -e
setopt NULL_GLOB  # Unmatched globs expand to nothing instead of aborting
unalias -a 2>/dev/null || true  # Prevent .zshenv aliases from leaking into script

TRAPZERR() {
  echo "ERROR: build-local.sh failed at ${funcfiletrace[1]:-line ${LINENO}} (exit code $?)" >&2
}

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
echo "==> Shell: zsh ${ZSH_VERSION}, arch: ${MACHINE_ARCH} (${ARCH_LABEL})"

function wipe_workspace {
  echo "==> Wiping workspace (preserving proven/, source/, and upstream clone)..."

  # Clean TARGET (~/opt/) — preserve proven cache and source tarballs
  local preserve_proven="${TARGET}/proven"
  local preserve_source="${TARGET}/source"

  for item in "${TARGET}"/*; do
    [[ "${item}" == "${preserve_proven}" ]] && continue
    [[ "${item}" == "${preserve_source}" ]] && continue
    echo "    Removing ${item:t}/"
    command rm -rf "${item}"
  done

  # Clean WORK_DIR (~/tmp/compile/) — preserve upstream clone and active log
  local preserve_clone="${WORK_DIR}/mkvtoolnix-src"

  for item in "${WORK_DIR}"/*; do
    [[ "${item}" == "${preserve_clone}" ]] && continue
    [[ "${item}" == "${LOG_FILE}" ]] && continue
    echo "    Removing ${item:t}"
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
BUILD_DIR="${SCRIPT_DIR}/build"
RELEASE_DIR="${SCRIPT_DIR}/release"
VERIFY_PASSED=false

function usage {
  cat <<'USAGE'
Usage: build-local.sh [options] <tag>

  tag               Upstream release tag (e.g. release-98.0)

Options:
  --full            Force full rebuild from source (proven cache untouched)
  --promote         Archive proven to LFS, replace with current build
  --restore-cache   Pull proven deps from LFS to local cache, then exit
  --cleanup-lfs     Restore proven/ to pointer files and prune LFS cache
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
    --restore-cache)  BUILD_MODE="restore-cache" ;;
    --cleanup-lfs)    BUILD_MODE="cleanup-lfs" ;;
    --help|-h)    usage ;;
    -*)           echo "Unknown option: $1"; usage ;;
    *)            TAG="$1" ;;
  esac
  shift
done

function cleanup_repo_lfs {
  local cleaned=false

  # Clean all architecture directories (arm, intel, or any future arch)
  for arch_dir in "${SCRIPT_DIR}"/proven/*(N/); do
    local arch_name="${arch_dir:t}"
    local sample_file=(${arch_dir}/*.tar.gz(N[1]))

    # Skip if no tar.gz files present
    [[ -z "${sample_file}" ]] && continue

    # Skip if already a pointer (LFS pointers start with "version https://git-lfs")
    if head -1 "${sample_file}" | grep -q "^version https://git-lfs"; then
      echo "    proven/${arch_name}/ already pointers."
      continue
    fi

    echo "    Restoring pointer files in proven/${arch_name}/..."
    (cd "${SCRIPT_DIR}" && GIT_LFS_SKIP_SMUDGE=1 git checkout -- "proven/${arch_name}/")
    cleaned=true
  done

  if [[ "${cleaned}" == true ]]; then
    echo "==> Pruning LFS object cache..."
    (cd "${SCRIPT_DIR}" && git lfs prune)
    echo "    Pruned LFS object cache."
  else
    echo "    No cleanup needed — all proven files are already pointers."
  fi
}

# Handle --cleanup-lfs early (no tag, clone, or specs needed)
if [[ "${BUILD_MODE}" == "cleanup-lfs" ]]; then
  echo "==> Cleaning up LFS objects..."
  cleanup_repo_lfs
  echo "==> Done. Repo proven/ restored to pointer files."
  exit 0
fi

if [[ -z "${TAG}" ]]; then
  TAG="release-98.0"
  echo "WARNING: No tag specified, defaulting to ${TAG}. Pass a tag explicitly for new versions."
fi
VERSION=${TAG#release-}

# Ensure required directories exist
mkdir -p "${TARGET}/include" "${TARGET}/lib" "${PACKAGE_DIR}" "${WORK_DIR}"

# Start logging — capture everything from here onward (including the build header)
LOG_FILE="${WORK_DIR}/build-${VERSION}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "${LOG_FILE}") 2>&1
BUILD_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SECONDS=0

# Build report function (defined early so EXIT trap can use it on any failure)
function write_report {
  local report_file="${WORK_DIR}/build-report-${VERSION}.txt"
  {
    local elapsed=$SECONDS
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    echo "Build Report: MKVToolNix ${VERSION}"
    echo "Started: ${BUILD_START_TIME}"
    echo "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Elapsed: ${mins}m $(printf '%02d' ${secs})s"
    echo "Architecture: ${MACHINE_ARCH} (${ARCH_LABEL})"
    echo "Mode: ${BUILD_MODE}"
    echo "Build: ${BUILD_SUMMARY:-unknown}"
    echo ""
    echo "Verification: $(if [[ "${VERIFY_PASSED}" == true ]]; then echo "PASSED"; else echo "FAILED"; fi)"
    [[ -n "${BUILT_QT_VERSION}" ]] && echo "Qt version: ${BUILT_QT_VERSION} (expected ${QTVER})"
    [[ -n "${size_mb}" ]] && echo "App size: ${size_mb} MB"
    echo ""
    [[ -n "${DMG_RELEASE_NAME}" ]] && echo "Release: ${RELEASE_DIR}/${DMG_RELEASE_NAME}"
    [[ -n "${DMG_NAME}" ]] && echo "Internal: ${BUILD_DIR}/${DMG_NAME}"
    [[ -n "${LOG_NAME}" ]] && echo "Log: ${LOG_DIR}/${LOG_NAME}"
    echo "Build log: ${LOG_FILE}"
  } > "${report_file}"
  echo "==> Build report: ${report_file}"
}

# Write build report on exit (success or failure)
trap '{
  BUILD_SUMMARY="${BUILD_SUMMARY:-FAILED (script exited unexpectedly)}"
  write_report
  sleep 0.1  # allow tee to flush
}' EXIT
trap 'echo "==> Interrupted."; exit 130' INT TERM HUP

echo "==> Building MKVToolNix ${VERSION} for ${MACHINE_ARCH} (${ARCH_LABEL})"
echo "==> Mode: ${BUILD_MODE}"
echo "==> Work directory: ${WORK_DIR}"
echo "==> Logging to ${LOG_FILE}"

# Clone upstream at the specified tag (or verify existing clone matches)
CLONE_DIR="${WORK_DIR}/mkvtoolnix-src"
if [[ ! -d "${CLONE_DIR}/.git" ]]; then
  echo "==> Cloning upstream ${TAG}..."
  git clone --depth 1 --branch "${TAG}" "${UPSTREAM_URL}" "${CLONE_DIR}"
else
  # Verify the clone is on the correct tag
  CURRENT_TAG=$(git -C "${CLONE_DIR}" describe --tags --exact-match 2>/dev/null || true)
  if [[ "${CURRENT_TAG}" != "${TAG}" ]]; then
    echo "==> Clone exists but is on ${CURRENT_TAG:-unknown}, need ${TAG}. Re-cloning..."
    command rm -rf "${CLONE_DIR}"
    git clone --depth 1 --branch "${TAG}" "${UPSTREAM_URL}" "${CLONE_DIR}"
  else
    echo "==> Source already cloned at ${CLONE_DIR} (${TAG})"
  fi
fi

# Reset source tree for clean patch application
cd "${CLONE_DIR}"
git checkout -- .
git clean -fd -q  # Remove untracked files from prior runs (qt-patches, config overlay, etc.)

# Copy our config overlay (after clean, so it doesn't get removed)
echo "==> Applying config overlay..."
command cp "${SCRIPT_DIR}/config/config.local.sh" "${CLONE_DIR}/packaging/macos/config.local.sh"

# Apply patches
echo "==> Applying patches..."
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
  [[ -f "${patch}" ]] || continue
  echo "    Applying ${patch:t}..."
  if git apply --check "${patch}" 2>/dev/null; then
    git apply "${patch}"
  elif git apply --reverse --check "${patch}" 2>/dev/null; then
    echo "    (already applied)"
  else
    echo "ERROR: Patch failed to apply: ${patch:t}"
    echo "  Not applicable forward or in reverse — may be outdated or broken"
    exit 1
  fi
done

# Copy Qt source patches (applied by upstream build.sh via qt-patches/ mechanism)
if [[ -d "${SCRIPT_DIR}/patches/qt-patches" ]]; then
  echo "==> Installing Qt source patches..."
  command cp -r "${SCRIPT_DIR}/patches/qt-patches" "${CLONE_DIR}/packaging/macos/qt-patches"
fi

# --- Pre-build verification ---

# Source the config files the same way build.sh does, to get QTVER
# Save our state — sourced files can disable set -e, change options, clobber vars
_SAVED_TARGET="${TARGET}"
_SAVED_WORK_DIR="${WORK_DIR}"
_SAVED_OPTS=$(setopt | tr '\n' ' ')
source "${CLONE_DIR}/packaging/macos/config.sh"
test -f "${CLONE_DIR}/packaging/macos/config.local.sh" && source "${CLONE_DIR}/packaging/macos/config.local.sh"
source "${CLONE_DIR}/packaging/macos/specs.sh"
# Restore our state — re-enable options that sourced files may have disabled
setopt ${=_SAVED_OPTS} 2>/dev/null
set -e
TARGET="${_SAVED_TARGET}"
WORK_DIR="${_SAVED_WORK_DIR}"
echo "==> Config: QTVER=${QTVER}, TARGET=${TARGET}, WORK_DIR=${WORK_DIR}"

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

# Derive expected package names from specs.sh (single source of truth for versions)
# Produces names like: autoconf-2.69, boost_1_88_0, qt-everywhere-src-6.10.2, etc.
EXPECTED_SPEC_VARS=(
  spec_autoconf spec_automake spec_pkgconfig spec_libiconv
  spec_cmake spec_ogg spec_vorbis spec_flac spec_zlib spec_gettext
  spec_cmark spec_gmp spec_boost spec_qt
)
EXPECTED_PACKAGES=()
for spec_var in "${EXPECTED_SPEC_VARS[@]}"; do
  filename="${${(P)spec_var}[1]}"
  if [[ -z "${filename}" ]]; then
    echo "ERROR: ${spec_var} not found in specs.sh — upstream may have renamed it"
    echo "  Check the upstream specs.sh and update EXPECTED_SPEC_VARS"
    exit 1
  fi
  pkg="${filename%%.tar.*}"
  EXPECTED_PACKAGES+=("${pkg}")
done
# Fix zlib naming (spec has zlib-v1.3.1, package is zlib-1.3.1)
EXPECTED_PACKAGES=("${EXPECTED_PACKAGES[@]/zlib-v/zlib-}")

# Clean stale build directories — derive glob prefixes from EXPECTED_PACKAGES
echo "==> Cleaning stale build directories..."
for pkg in "${EXPECTED_PACKAGES[@]}"; do
  # Extract the name prefix before the version (e.g., "autoconf" from "autoconf-2.69")
  pkg_prefix="${pkg%%-[0-9]*}"
  [[ "${pkg_prefix}" == "${pkg}" ]] && pkg_prefix="${pkg%%_[0-9]*}"  # handle boost_1_88_0
  for stale_dir in "${WORK_DIR}/${pkg_prefix}"*; do
    if [[ -d "${stale_dir}" ]] && [[ "${stale_dir:t}" != "${pkg}" ]]; then
      echo "    Removing stale: ${stale_dir:t}"
      command rm -rf "${stale_dir}"
    fi
  done
done

# --- Dependency caching logic ---

function restore_from_proven {
  local proven_dir="${TARGET}/proven/${ARCH_LABEL}"
  local restored=0
  local missing=()

  echo "==> Restoring from proven cache..."

  for pkg in "${EXPECTED_PACKAGES[@]}"; do
    local pkg_file="${proven_dir}/${pkg}.tar.gz"
    if [[ -f "${pkg_file}" ]]; then
      echo "    Restoring ${pkg}..."
      (cd "${TARGET}" && tar xzf "${pkg_file}")
      restored=$((restored + 1))
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
    restored=$((restored + 1))
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
  local proven_dir="${TARGET}/proven/${ARCH_LABEL}"
  local packages_dir="${TARGET}/packages"
  local repo_proven="${SCRIPT_DIR}/proven/${ARCH_LABEL}"

  # Precondition: verification must have passed
  if [[ "${VERIFY_PASSED}" != true ]]; then
    echo "ERROR: Cannot promote — post-build verification did not pass."
    echo "       Build and verify first, then promote."
    exit 1
  fi

  # Precondition: packages must contain all expected deps + docbook-xsl
  local missing_pkgs=()
  for pkg in "${EXPECTED_PACKAGES[@]}"; do
    [[ -f "${packages_dir}/${pkg}.tar.gz" ]] || missing_pkgs+=("${pkg}")
  done
  [[ -f "${packages_dir}/docbook-xsl.tar.gz" ]] || missing_pkgs+=("docbook-xsl")
  if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    echo "ERROR: Cannot promote — packages/ is incomplete (${#missing_pkgs[@]} missing)."
    echo "  Missing: ${missing_pkgs[*]}"
    echo "  This can happen after a smart-restore build (only mkvtoolnix was rebuilt)."
    echo "  Run a --full build first, then promote."
    exit 1
  fi

  echo "==> Promoting ${#EXPECTED_PACKAGES[@]} packages + docbook-xsl (${ARCH_LABEL})..."

  # Step 1: Archive current proven to LFS
  local proven_files=(${proven_dir}/*.tar.gz)
  if [[ -d "${proven_dir}" ]] && [[ ${#proven_files[@]} -gt 0 ]]; then
    echo "    Archiving current ${ARCH_LABEL} proven to LFS..."
    mkdir -p "${repo_proven}"
    command cp "${proven_dir}"/*.tar.gz "${repo_proven}/"
    (cd "${SCRIPT_DIR}" && git add "proven/${ARCH_LABEL}/"*.tar.gz && git diff --cached --quiet || git commit -m "archive: ${ARCH_LABEL} proven deps before promotion $(date +%Y-%m-%d)" -- "proven/${ARCH_LABEL}/")
  fi

  # Step 2: Build new proven set in temp directory
  local pkg_files=("${packages_dir}"/*.tar.gz)
  if [[ ${#pkg_files[@]} -eq 0 ]]; then
    echo "ERROR: No packages found in ${packages_dir} — cannot promote."
    exit 1
  fi
  local proven_new="${TARGET}/proven-${ARCH_LABEL}-new"
  mkdir -p "${proven_new}"
  command cp "${pkg_files[@]}" "${proven_new}/"

  # Step 3: Atomic swap — clean up stale old dir first to prevent nesting
  command rm -rf "${TARGET}/proven-${ARCH_LABEL}-old"
  if [[ -d "${proven_dir}" ]]; then
    command mv "${proven_dir}" "${TARGET}/proven-${ARCH_LABEL}-old"
  fi
  mkdir -p "${TARGET}/proven"
  command mv "${proven_new}" "${proven_dir}"

  # Step 4: Cleanup old
  if [[ -d "${TARGET}/proven-${ARCH_LABEL}-old" ]]; then
    command rm -rf "${TARGET}/proven-${ARCH_LABEL}-old"
  fi

  # Step 5: Update LFS with new proven
  mkdir -p "${repo_proven}"
  command cp "${proven_dir}"/*.tar.gz "${repo_proven}/"
  (cd "${SCRIPT_DIR}" && git add "proven/${ARCH_LABEL}/"*.tar.gz && git diff --cached --quiet || git commit -m "promote: ${ARCH_LABEL} proven deps $(date +%Y-%m-%d)" -- "proven/${ARCH_LABEL}/")

  echo "==> Promotion complete. Proven cache updated."
  echo "    LFS archive committed. Push when ready."

  # Clean up repo working copy to reclaim disk space
  cleanup_repo_lfs
}

# --- Build ---

cd "${CLONE_DIR}/packaging/macos"

case "${BUILD_MODE}" in
  full)
    echo "==> Full build (all dependencies + mkvtoolnix from source)..."
    BUILD_SUMMARY="Full build from source"
    wipe_workspace
    ./build.sh
    ;;
  promote)
    local promote_pkgs=("${TARGET}/packages"/*.tar.gz)
    if [[ ! -d "${TARGET}/packages" ]] || [[ ${#promote_pkgs[@]} -eq 0 ]]; then
      echo "ERROR: No build packages found. Build first, then promote."
      exit 1
    fi
    BUILD_SUMMARY="Promote (verification only)"
    echo "==> Promote mode — skipping build, running verification..."
    ;;
  restore-cache)
    echo "==> Restoring proven cache from LFS for ${ARCH_LABEL}..."

    local repo_proven="${SCRIPT_DIR}/proven/${ARCH_LABEL}"
    local local_proven="${TARGET}/proven/${ARCH_LABEL}"

    # Check if LFS pointers exist in repo
    local pointer_files=(${repo_proven}/*.tar.gz(N))
    if [[ ${#pointer_files[@]} -eq 0 ]]; then
      echo "ERROR: No proven files found in proven/${ARCH_LABEL}/"
      echo "  The repository may not have a proven cache for this architecture."
      exit 1
    fi

    # Pull LFS objects for this arch only (override fetchexclude)
    echo "    Pulling LFS objects for ${ARCH_LABEL}..."
    (cd "${SCRIPT_DIR}" && git lfs pull --include="proven/${ARCH_LABEL}/" --exclude="")

    # Verify ALL files are real content (not still pointers)
    local still_pointers=()
    for f in "${pointer_files[@]}"; do
      if head -1 "${f}" | grep -q "^version https://git-lfs"; then
        still_pointers+=("${f:t}")
      fi
    done
    if [[ ${#still_pointers[@]} -gt 0 ]]; then
      echo "ERROR: LFS pull did not download all files."
      echo "  ${#still_pointers[@]} files are still pointers:"
      echo "    ${still_pointers[*]}"
      echo "  Check your network connection and LFS access."
      exit 1
    fi

    # Copy to local cache
    mkdir -p "${local_proven}"
    echo "    Copying to ${local_proven}..."
    command cp "${repo_proven}"/*.tar.gz "${local_proven}/"

    # Verify expected packages arrived
    local restored=0
    local missing=()
    for pkg in "${EXPECTED_PACKAGES[@]}"; do
      if [[ -f "${local_proven}/${pkg}.tar.gz" ]]; then
        restored=$((restored + 1))
      else
        missing+=("${pkg}")
      fi
    done
    [[ -f "${local_proven}/docbook-xsl.tar.gz" ]] && restored=$((restored + 1)) || missing+=("docbook-xsl")

    echo "    Restored ${restored} packages to local cache."
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "    WARNING: ${#missing[@]} expected packages missing from LFS:"
      echo "      ${missing[*]}"
    fi

    # Clean up repo working copy
    cleanup_repo_lfs

    BUILD_SUMMARY="Restore cache from LFS (${restored} packages)"
    echo "==> Done. Local cache ready at ${local_proven}"
    echo "    Run './build-local.sh ${TAG}' to build using cached deps."
    exit 0
    ;;
  auto|"")
    wipe_workspace
    if restore_from_proven; then
      BUILD_SUMMARY="Restored from proven, built mkvtoolnix only"
      echo "==> All dependencies restored from proven. Building mkvtoolnix only..."
      ./build.sh mkvtoolnix
    else
      BUILD_SUMMARY="No proven cache, full build from source"
      echo "==> Some dependencies missing from proven. Doing full build..."
      ./build.sh
    fi
    ;;
esac

# Post-build fixups and DMG (skip for promote mode — packages already exist)
if [[ "${BUILD_MODE}" != "promote" ]]; then
  # Rename unversioned cmark package to include version
  if [[ -f "${TARGET}/packages/mtx-build.tar.gz" ]]; then
    cmark_version=$(echo "${EXPECTED_PACKAGES[@]}" | tr ' ' '\n' | grep "^cmark-" || true)
    if [[ -n "${cmark_version}" ]]; then
      echo "==> Renaming mtx-build.tar.gz to ${cmark_version}.tar.gz"
      command mv "${TARGET}/packages/mtx-build.tar.gz" "${TARGET}/packages/${cmark_version}.tar.gz"
    fi
  fi

  # Archive docbook-xsl if not already in packages
  if [[ -d "${TARGET}/xsl-stylesheets" ]] && [[ ! -f "${TARGET}/packages/docbook-xsl.tar.gz" ]]; then
    local docbook_dirs=("${TARGET}"/docbook-xsl-*)
    if [[ ${#docbook_dirs[@]} -gt 0 ]]; then
      echo "==> Archiving docbook-xsl..."
      (cd "${TARGET}" && tar czf "${TARGET}/packages/docbook-xsl.tar.gz" xsl-stylesheets "${docbook_dirs[@]:t}")
    else
      echo "WARNING: xsl-stylesheets exists but no docbook-xsl-* directories found — archive may be incomplete"
      (cd "${TARGET}" && tar czf "${TARGET}/packages/docbook-xsl.tar.gz" xsl-stylesheets)
    fi
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
  BUILT_QT_VERSION=$(otool -L "${DMG_APP}/Contents/MacOS/mkvtoolnix-gui" 2>/dev/null | grep libQt6Core | sed 's/.*current version \([0-9.]*\).*/\1/' || true)
  if [[ -n "${BUILT_QT_VERSION}" ]]; then
    if [[ "${BUILT_QT_VERSION}" == "${QTVER}" ]]; then
      echo "    PASS: Qt version ${BUILT_QT_VERSION} matches expected ${QTVER}"
    else
      echo "    FAIL: Qt version mismatch — binary has ${BUILT_QT_VERSION}, expected ${QTVER}"
      VERIFY_PASSED=false
    fi
  else
    echo "    FAIL: Could not determine Qt version from binary"
    VERIFY_PASSED=false
  fi

  # 2. Architecture check on ALL binaries and dylibs
  arch_errors=0
  arch_checked=0
  expected_arch="${MACHINE_ARCH}"
  if [[ -d "${DMG_APP}/Contents/MacOS" ]]; then
    while IFS= read -r -d '' binary; do
      file_info=$(file "${binary}" 2>/dev/null || true)
      # Skip non-Mach-O files (scripts, text, etc.)
      [[ "${file_info}" == *"Mach-O"* ]] || continue
      arch_checked=$((arch_checked + 1))
      if [[ "${file_info}" != *"${expected_arch}"* ]]; then
        echo "    FAIL: Wrong architecture in ${binary:t} (expected ${expected_arch})"
        arch_errors=$((arch_errors + 1))
        VERIFY_PASSED=false
      fi
    # Note: -perm +111 is BSD find syntax (deprecated but macOS /usr/bin/find doesn't support -perm /111)
    done < <(/usr/bin/find "${DMG_APP}/Contents/MacOS" \( -name "*.dylib" -o -type f -perm +111 \) -not -type d -print0 2>/dev/null)
  fi
  if [[ ${arch_checked} -eq 0 ]]; then
    echo "    FAIL: No binaries found to check architecture"
    VERIFY_PASSED=false
  elif [[ ${arch_errors} -eq 0 ]]; then
    echo "    PASS: All ${arch_checked} binaries and dylibs are ${expected_arch}"
  fi

  # 3. Duplicate dylib scan
  dupes=$(/usr/bin/find "${DMG_APP}/Contents/MacOS/libs" -name "*.dylib" -not -type l 2>/dev/null | sed 's/\(\.[0-9][0-9]*\)*\.dylib/.dylib/' | sort | uniq -d)
  if [[ -n "${dupes}" ]]; then
    echo "    FAIL: Duplicate dylib versions found:"
    echo "${dupes}" | while read -r d; do echo "      ${d}"; done
    VERIFY_PASSED=false
  else
    echo "    PASS: No duplicate dylib versions"
  fi

  # 4. Size sanity check (decimal MB to match Finder)
  app_bytes=$(/usr/bin/find "${DMG_APP}" -type f -exec /usr/bin/stat -f '%z' {} + 2>/dev/null | awk '{s+=$1} END {print s}')
  size_mb=$(echo "${app_bytes}" | awk '{printf "%.1f", $1/1000/1000}')
  min_size=60  # MB — below this something is missing
  max_size=95  # MB — above this something is duplicated
  if (( $(echo "${size_mb} < ${min_size}" | bc -l) )); then
    echo "    FAIL: App is ${size_mb} MB — suspiciously small (expected ${min_size}-${max_size} MB)"
    VERIFY_PASSED=false
  elif (( $(echo "${size_mb} > ${max_size}" | bc -l) )); then
    echo "    FAIL: App is ${size_mb} MB — suspiciously large (expected ${min_size}-${max_size} MB)"
    VERIFY_PASSED=false
  else
    echo "    PASS: App size ${size_mb} MB (expected range ${min_size}-${max_size} MB)"
  fi

  # 5. Homebrew / external library leak detection
  leak_found=false
  for lib in "${DMG_APP}/Contents/MacOS/libs/"*.dylib "${DMG_APP}/Contents/MacOS/"mkvtoolnix-gui; do
    leaks=$(otool -L "$lib" 2>/dev/null | grep -E "/opt/homebrew|/usr/local/opt" || true)
    if [[ -n "$leaks" ]]; then
      echo "    FAIL: External library reference in $(basename $lib):"
      echo "$leaks" | while read -r line; do echo "      $line"; done
      leak_found=true
      VERIFY_PASSED=false
    fi
  done
  if [[ "$leak_found" == false ]]; then
    echo "    PASS: No Homebrew/external library references"
  fi

  # 6. Bundle inventory
  echo "    --- Bundle inventory ---"
  /usr/bin/find "${DMG_APP}/Contents/MacOS/libs" -name "*.dylib" -not -type l 2>/dev/null | while read -r lib; do
    echo "    $(basename "${lib}")"
  done

  # Summary
  if [[ "${VERIFY_PASSED}" == true ]]; then
    echo "==> Verification: ALL CHECKS PASSED"
  else
    echo "==> Verification: SOME CHECKS FAILED — review output above"
  fi
else
  if [[ "${BUILD_MODE}" == "promote" ]]; then
    echo "ERROR: App bundle not found at ${DMG_APP}"
    echo "  The DMG from the previous build may have been cleaned. Build again first."
  else
    echo "==> WARNING: App bundle not found at ${DMG_APP} — skipping verification"
  fi
  VERIFY_PASSED=false
fi

# Handle promotion after verification
if [[ "${BUILD_MODE}" == "promote" ]]; then
  do_promote
  exit 0
fi

# --- Name and copy DMG ---

BUILD_COUNTER_FILE="${SCRIPT_DIR}/.build-counter-${ARCH_LABEL}"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${BUILD_DIR}" "${RELEASE_DIR}" "${LOG_DIR}"

DMG_PATH="${WORK_DIR}/MKVToolNix-${VERSION}.dmg"

if [[ -f "${DMG_PATH}" ]]; then
  # Increment global build counter (atomic write via temp+mv)
  if [[ -f "${BUILD_COUNTER_FILE}" ]]; then
    BUILD_NUM=$(( $(cat "${BUILD_COUNTER_FILE}") + 1 ))
  else
    BUILD_NUM=1
  fi
  echo "${BUILD_NUM}" > "${BUILD_COUNTER_FILE}.tmp" && command mv "${BUILD_COUNTER_FILE}.tmp" "${BUILD_COUNTER_FILE}"

  # Get current git branch name for the label (sanitize slashes for filename)
  BRANCH=$(cd "${SCRIPT_DIR}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  [[ "${BRANCH}" == "HEAD" ]] && BRANCH=$(cd "${SCRIPT_DIR}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  BRANCH="${BRANCH//\//-}"

  BUILD_LABEL="b$(printf '%03d' ${BUILD_NUM})"
  DMG_NAME="MKVToolNix-${VERSION}-macos-${ARCH_LABEL}-${BUILD_LABEL}-${BRANCH}.dmg"
  DMG_RELEASE_NAME="MKVToolNix-${VERSION}-macos-${ARCH_LABEL}.dmg"
  LOG_NAME="MKVToolNix-${VERSION}-macos-${ARCH_LABEL}-${BUILD_LABEL}-${BRANCH}.log"
  command cp "${DMG_PATH}" "${BUILD_DIR}/${DMG_NAME}"
  command cp "${DMG_PATH}" "${RELEASE_DIR}/${DMG_RELEASE_NAME}"
  command cp "${LOG_FILE}" "${LOG_DIR}/${LOG_NAME}"
  echo "==> Done!"
  echo "    Build output: ${DMG_PATH}"
  echo "    Internal: ${BUILD_DIR}/${DMG_NAME}"
  echo "    Release:  ${RELEASE_DIR}/${DMG_RELEASE_NAME}"
  echo "    Log:      ${LOG_DIR}/${LOG_NAME}"
else
  echo "==> DMG not found at expected path. Check ${WORK_DIR} for output."
  command ls -la "${WORK_DIR}"/MKVToolNix*.dmg 2>/dev/null || true
fi
