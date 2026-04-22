#!/bin/zsh
# tools/build-fork.sh — Build MKVToolNix from a fork/worktree source tree.
#
# For experimental/forked-branch builds only. Does NOT produce release
# artifacts. Compiles the given source with the proven + experimental dep
# caches (experimental overlays proven, e.g. Qt 6.11.0 wins over 6.10.2),
# produces a DMG in build/ with a fork-specific filename, and never copies
# to release/.
#
# Usage: ./tools/build-fork.sh <path-to-source> [--slug NAME] [--verify-symbol SYM]

if [[ -z "${ZSH_VERSION}" ]]; then
  echo "ERROR: This script requires zsh. Run it with: ./tools/build-fork.sh" >&2
  exit 1
fi
if [[ "${ZSH_EVAL_CONTEXT}" == *:file ]]; then
  echo "ERROR: This script must be executed, not sourced." >&2
  return 1
fi

set -e
setopt NULL_GLOB
unalias -a 2>/dev/null || true

TRAPZERR() {
  echo "ERROR: build-fork.sh failed at ${funcfiletrace[1]:-line ${LINENO}} (exit code $?)" >&2
}

# SCRIPT_DIR = wrapper repo root (tools/ → parent)
SCRIPT_DIR=${0:a:h:h}

usage() {
  cat <<'USAGE'
Usage: ./tools/build-fork.sh <path-to-source> [--slug NAME] [--verify-symbol SYM]

Build MKVToolNix from a fork/worktree source tree. Produces a DMG in
build/ with a fork-specific filename. Uses proven + experimental dep
caches (experimental wins on conflicts, e.g. Qt 6.11.0 > 6.10.2).

For experimental and forked-branch builds only. Never copies to release/.

Arguments:
  <path-to-source>         Absolute path to a mkvtoolnix source tree
                           (e.g., a git worktree checkout).

Options:
  --slug NAME              DMG filename suffix. Defaults to basename
                           of source path (with leading "mkvtoolnix-
                           upstream-" stripped if present).
  --verify-symbol SYM      Verify the built binary contains this string
                           before declaring success. Abort if missing.
                           Intended to catch "patch didn't compile in"
                           failure mode. Example: lastProgramRunnerAudioDir
  --help, -h               Show this help.
USAGE
}

# --- Arg parsing ---
SRC=""
SLUG=""
VERIFY_SYMBOL=""
while [[ -n $1 ]]; do
  case $1 in
    --slug)
      shift
      SLUG="$1"
      ;;
    --verify-symbol)
      shift
      VERIFY_SYMBOL="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "${SRC}" ]]; then
        SRC="$1"
      else
        echo "ERROR: Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "${SRC}" ]]; then
  echo "ERROR: source path required" >&2
  usage >&2
  exit 1
fi

# Absolutize source path
SRC=${SRC:a}
if [[ ! -d "${SRC}" ]]; then
  echo "ERROR: source path does not exist: ${SRC}" >&2
  exit 1
fi

# --- Sanity: source looks like mkvtoolnix ---
if [[ ! -f "${SRC}/configure.ac" ]] || [[ ! -d "${SRC}/src/mkvtoolnix-gui" ]] || [[ ! -f "${SRC}/packaging/macos/build.sh" ]]; then
  echo "ERROR: ${SRC} does not look like a mkvtoolnix source tree" >&2
  echo "       Expected: configure.ac, src/mkvtoolnix-gui/, packaging/macos/build.sh" >&2
  exit 1
fi

# --- Ensure git submodules are populated ---
# mkvtoolnix uses submodules for lib/libebml, lib/libmatroska, lib/fmt.
# configure fails without them. git submodule update is idempotent — fast
# no-op if already initialized. Done in SRC (which has .git), not in the
# rsync'd copy.
if [[ -d "${SRC}/.git" ]] || [[ -f "${SRC}/.git" ]]; then
  echo "==> Ensuring git submodules are initialized in ${SRC}..."
  (cd "${SRC}" && git submodule update --init --recursive)
else
  echo "WARNING: ${SRC} is not a git checkout — skipping submodule init."
  echo "         If build fails with missing libEBML/libMatroska/fmt, you need"
  echo "         to populate lib/libebml, lib/libmatroska, lib/fmt manually." >&2
fi

# --- Architecture ---
MACHINE_ARCH=$(uname -m)
if [[ "${MACHINE_ARCH}" == "arm64" ]]; then
  ARCH_LABEL="arm"
elif [[ "${MACHINE_ARCH}" == "x86_64" ]]; then
  ARCH_LABEL="intel"
else
  ARCH_LABEL="${MACHINE_ARCH}"
fi

# --- Slug defaulting ---
if [[ -z "${SLUG}" ]]; then
  SLUG="${SRC:t}"
  SLUG="${SLUG#mkvtoolnix-upstream-}"
fi
# Sanitize: allow only [A-Za-z0-9_-]
SLUG="${SLUG//[^a-zA-Z0-9_-]/-}"

# --- MTX_VER from worktree's configure.ac ---
MTX_VER=$(awk -F, '/AC_INIT/ { gsub("[][]", "", $2); print $2 }' "${SRC}/configure.ac")
if [[ -z "${MTX_VER}" ]]; then
  echo "ERROR: Could not derive MTX_VER from ${SRC}/configure.ac" >&2
  exit 1
fi

# --- Paths: honor env overrides, default to upstream's convention ---
WORK_DIR="${WORK_DIR:-${HOME}/tmp/compile}"
TARGET="${TARGET:-${HOME}/opt}"

# --- Predict build number and derive hash (deterministic from slug+num+ver) ---
# Counter only increments on success, so a failed build's retry gets the same
# number and therefore the same hash — each "slot" has a stable identifier.
BUILD_COUNTER_FILE="${SCRIPT_DIR}/.build-counter-${ARCH_LABEL}"
if [[ -f "${BUILD_COUNTER_FILE}" ]]; then
  BUILD_NUM=$(( $(cat "${BUILD_COUNTER_FILE}") + 1 ))
else
  BUILD_NUM=1
fi
BUILD_LABEL="b$(printf '%03d' ${BUILD_NUM})"
BUILD_HASH=$(print -n "${SLUG}|${BUILD_NUM}|${MTX_VER}" | shasum -a 256 | head -c 6)
VERSIONNAME="99pre-exp-${SLUG}-${BUILD_LABEL}-${BUILD_HASH}"

echo "==> build-fork.sh"
echo "    Source:      ${SRC}"
echo "    Slug:        ${SLUG}"
echo "    MTX_VER:     ${MTX_VER}"
echo "    Arch:        ${MACHINE_ARCH} (${ARCH_LABEL})"
echo "    WORK_DIR:    ${WORK_DIR}"
echo "    TARGET:      ${TARGET}"
echo "    Build num:   ${BUILD_NUM} (predicted — counter bumps on success)"
echo "    Build hash:  ${BUILD_HASH} (deterministic: slug+num+ver)"
echo "    VERSIONNAME: ${VERSIONNAME}"
if [[ -n "${VERIFY_SYMBOL}" ]]; then
  echo "    VerifySym:   ${VERIFY_SYMBOL}"
fi

# --- Log setup ---
mkdir -p "${WORK_DIR}"
LOG_FILE="${WORK_DIR}/build-fork-${SLUG}-${BUILD_LABEL}-${BUILD_HASH}.log"
exec > >(tee "${LOG_FILE}") 2>&1
BUILD_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SECONDS=0

trap 'echo "==> Interrupted."; exit 130' INT TERM HUP

# --- Wipe workspace (preserve proven, proven-experimental, source) ---
echo "==> Wiping workspace TARGET (preserve proven/, proven-experimental/, source/)..."
for item in "${TARGET}"/*; do
  case "${item:t}" in
    proven|proven-experimental|source) continue ;;
  esac
  [[ -e "${item}" ]] && echo "    rm -rf ${item:t}" && command rm -rf "${item}"
done
mkdir -p "${TARGET}/include" "${TARGET}/lib" "${TARGET}/bin" "${TARGET}/packages"

# Clean out prior fork-build scratch dir for this MTX_VER
FORK_BUILD_DIR="${WORK_DIR}/mkvtoolnix-${MTX_VER}"
if [[ -d "${FORK_BUILD_DIR}" ]]; then
  echo "    rm -rf ${FORK_BUILD_DIR:t} (prior fork-build scratch)"
  command rm -rf "${FORK_BUILD_DIR}"
fi

# Remove prior DMG staging for this version
command rm -rf "${WORK_DIR}/dmg-${MTX_VER}" "${WORK_DIR}/MKVToolNix-${MTX_VER}.dmg" 2>/dev/null || true

# --- Restore deps: proven first, experimental overlays on top ---
PROVEN_DIR="${TARGET}/proven/${ARCH_LABEL}"
EXPERIMENTAL_DIR="${TARGET}/proven-experimental/${ARCH_LABEL}"

if [[ ! -d "${PROVEN_DIR}" ]]; then
  echo "ERROR: Proven cache not found at ${PROVEN_DIR}" >&2
  echo "       Run './build-local.sh --restore-cache' first." >&2
  exit 1
fi

# Spec-aware restore: read the worktree's specs.sh to discover which exact
# package name is wanted for each dependency. For each expected package, pick
# experimental if it has the matching filename, else proven. Skip proven packages
# whose names don't match the spec (e.g., older Qt/zlib versions that would
# otherwise bundle alongside experimental and bloat the DMG).
echo "==> Discovering expected packages from worktree specs.sh..."
_SAVED_OPTS_RESTORE=$(setopt | tr '\n' ' ')
source "${SRC}/packaging/macos/specs.sh"
setopt ${=_SAVED_OPTS_RESTORE} 2>/dev/null
set -e

EXPECTED_PACKAGES=()
# Deliberately omit spec_curl — mkvtoolnix compile doesn't link curl, and the
# wrapper's proven cache predates its addition to upstream specs.
for spec_var in spec_autoconf spec_automake spec_pkgconfig spec_libiconv \
                spec_cmake spec_ogg spec_vorbis spec_flac spec_zlib spec_gettext \
                spec_cmark spec_gmp spec_boost spec_qt; do
  filename="${${(P)spec_var}[1]}"
  [[ -z "${filename}" ]] && continue
  pkg="${filename%%.tar.*}"
  EXPECTED_PACKAGES+=("${pkg}")
done
# Normalize zlib filename — specs use "zlib-vN.N.N" in source-tarball URL, but
# the built package is named "zlib-N.N.N" (no "v"). Matches build-local.sh.
EXPECTED_PACKAGES=("${EXPECTED_PACKAGES[@]/zlib-v/zlib-}")

echo "==> Expected packages (${#EXPECTED_PACKAGES[@]}): ${EXPECTED_PACKAGES[*]}"

echo "==> Restoring packages (experimental wins on match)..."
restored=0
from_experimental=0
from_proven=0
missing=()
for pkg in "${EXPECTED_PACKAGES[@]}"; do
  if [[ -f "${EXPERIMENTAL_DIR}/${pkg}.tar.gz" ]]; then
    echo "    ${pkg} (experimental)"
    (cd "${TARGET}" && tar xzf "${EXPERIMENTAL_DIR}/${pkg}.tar.gz")
    from_experimental=$((from_experimental + 1))
    restored=$((restored + 1))
  elif [[ -f "${PROVEN_DIR}/${pkg}.tar.gz" ]]; then
    echo "    ${pkg}"
    (cd "${TARGET}" && tar xzf "${PROVEN_DIR}/${pkg}.tar.gz")
    from_proven=$((from_proven + 1))
    restored=$((restored + 1))
  else
    echo "    MISSING: ${pkg}"
    missing+=("${pkg}")
  fi
done

# Special-case docbook-xsl — not a standard spec name, handled separately.
if [[ -f "${EXPERIMENTAL_DIR}/docbook-xsl.tar.gz" ]]; then
  echo "    docbook-xsl (experimental)"
  (cd "${TARGET}" && tar xzf "${EXPERIMENTAL_DIR}/docbook-xsl.tar.gz")
  from_experimental=$((from_experimental + 1))
elif [[ -f "${PROVEN_DIR}/docbook-xsl.tar.gz" ]]; then
  echo "    docbook-xsl"
  (cd "${TARGET}" && tar xzf "${PROVEN_DIR}/docbook-xsl.tar.gz")
  from_proven=$((from_proven + 1))
fi

echo "==> Restored ${restored} packages (${from_experimental} experimental, ${from_proven} proven)."
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "WARN: ${#missing[@]} expected package(s) missing from both caches:" >&2
  for m in "${missing[@]}"; do echo "      - ${m}" >&2; done
  echo "      Build may fail. Run './build-local.sh --restore-cache' if needed." >&2
fi

# --- Stage source into WORK_DIR (upstream build.sh expects ${CMPL}/mkvtoolnix-${MTX_VER}) ---
echo "==> Staging source to ${FORK_BUILD_DIR}..."
mkdir -p "${FORK_BUILD_DIR}"
rsync -a \
  --exclude='.git' \
  --exclude='.DS_Store' \
  --exclude='*.o' \
  --exclude='*.a' \
  --exclude='*.moc' \
  --exclude='/build-config' \
  --exclude='/src/mkvmerge' \
  --exclude='/src/mkvextract' \
  --exclude='/src/mkvinfo' \
  --exclude='/src/mkvpropedit' \
  --exclude='/src/mkvtoolnix-gui/mkvtoolnix-gui' \
  "${SRC}/" \
  "${FORK_BUILD_DIR}/"

# --- Copy wrapper's config.local.sh into staged packaging dir ---
# Upstream build.sh sources config.local.sh from its own directory (packaging/
# macos/) if present. This is how our SIGNATURE_IDENTITY="-" (ad-hoc signing)
# and DRAKETHREADS=12 overrides reach build.sh's subprocesses. Without this
# copy, build.sh's own config.sh resets SIGNATURE_IDENTITY to mbunkus's cert
# identity, which we don't have, causing codesign failure.
if [[ -f "${SCRIPT_DIR}/config/config.local.sh" ]]; then
  echo "==> Copying wrapper config.local.sh into staged packaging dir..."
  command cp "${SCRIPT_DIR}/config/config.local.sh" \
    "${FORK_BUILD_DIR}/packaging/macos/config.local.sh"
fi

# --- Inject VERSIONNAME into staged source ---
# Uses the same perl substitution pattern as upstream's
# tools/development/bump_version_set_code_name.sh.
# Shows up as "v<MTX_VER> ('<VERSIONNAME>')" in About dialog, version logs, etc.
VERSION_FILE="${FORK_BUILD_DIR}/src/common/version.cpp"
if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "ERROR: ${VERSION_FILE} missing after stage — cannot inject VERSIONNAME." >&2
  exit 1
fi
echo "==> Setting VERSIONNAME = ${VERSIONNAME}"
perl -pi -e "s{^constexpr.*VERSIONNAME.*}{constexpr auto VERSIONNAME = \"${VERSIONNAME}\";}" "${VERSION_FILE}"
# Verify the substitution actually happened
if ! /usr/bin/grep -q "VERSIONNAME = \"${VERSIONNAME}\"" "${VERSION_FILE}"; then
  echo "ERROR: VERSIONNAME injection failed — source unchanged." >&2
  exit 1
fi

# --- Environment for upstream build.sh ---
# Source upstream's config.sh (provides CMPL, RAKE, MACOSX_DEPLOYMENT_TARGET, etc.)
# then wrapper's config.local.sh (provides SIGNATURE_IDENTITY="-", DRAKETHREADS=12, -O2).
_SAVED_OPTS=$(setopt | tr '\n' ' ')
source "${FORK_BUILD_DIR}/packaging/macos/config.sh"
if [[ -f "${SCRIPT_DIR}/config/config.local.sh" ]]; then
  source "${SCRIPT_DIR}/config/config.local.sh"
fi
# Re-enable our options after sourced files may have changed them
setopt ${=_SAVED_OPTS} 2>/dev/null
set -e

# Normalize paths — upstream config.sh hardcodes $HOME/tmp/compile; honor our WORK_DIR if different
export CMPL="${WORK_DIR}"
export TARGET
export SRCDIR="${SRCDIR:-${HOME}/opt/source}"
export MTX_VER
export NO_EXTRACTION=1  # critical: source already staged, don't let build_package wipe+re-extract

echo "==> Build environment:"
echo "    CMPL:        ${CMPL}"
echo "    TARGET:      ${TARGET}"
echo "    SRCDIR:      ${SRCDIR}"
echo "    MTX_VER:     ${MTX_VER}"
echo "    QTVER:       ${QTVER:-<unset>}"
echo "    DRAKETHREADS: ${DRAKETHREADS:-4}"
echo "    MACOSX_DEPLOYMENT_TARGET: ${MACOSX_DEPLOYMENT_TARGET}"
echo "    SIGNATURE_IDENTITY: ${SIGNATURE_IDENTITY:-<unset>}"
echo "    NO_EXTRACTION: ${NO_EXTRACTION}"

# --- Generate ./configure via autogen.sh ---
# Git checkouts don't include a pre-generated `configure`; release tarballs do.
# autogen.sh produces it via autoconf + automake (both present in proven cache).
echo ""
echo "==> Running autogen.sh to generate ./configure..."
if [[ ! -x "${FORK_BUILD_DIR}/autogen.sh" ]]; then
  echo "ERROR: ${FORK_BUILD_DIR}/autogen.sh missing or not executable." >&2
  exit 1
fi
(cd "${FORK_BUILD_DIR}" && ./autogen.sh)
if [[ ! -f "${FORK_BUILD_DIR}/configure" ]]; then
  echo "ERROR: autogen.sh ran but ${FORK_BUILD_DIR}/configure was not produced." >&2
  exit 1
fi

# --- Compile ---
echo ""
echo "==> Building mkvtoolnix (this is the long step)..."
cd "${FORK_BUILD_DIR}/packaging/macos"
./build.sh mkvtoolnix

echo ""
echo "==> Packaging DMG..."
./build.sh dmg

# --- DMG + binary verification ---
DMG_PATH="${WORK_DIR}/MKVToolNix-${MTX_VER}.dmg"
APP_BUNDLE="${WORK_DIR}/dmg-${MTX_VER}/MKVToolNix-${MTX_VER}.app"
BINARY="${APP_BUNDLE}/Contents/MacOS/mkvtoolnix-gui"

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "ERROR: Expected DMG not found at ${DMG_PATH}" >&2
  exit 1
fi
if [[ ! -f "${BINARY}" ]]; then
  echo "ERROR: Built binary not found at ${BINARY}" >&2
  exit 1
fi

# --- Patch-presence verification ---
# Goes beyond "is the string in the binary" — checks that the fork's changes
# survived compilation end-to-end. Still a smoke test (can't prove behavior
# from inspection alone), but catches cases where the code string is present
# yet the integration is broken.
if [[ -n "${VERIFY_SYMBOL}" ]]; then
  echo ""
  echo "==> Patch-presence verification: ${VERIFY_SYMBOL}"

  # 1. Presence + occurrence count in binary
  symbol_count=$(/usr/bin/strings "${BINARY}" | /usr/bin/grep -c -- "${VERIFY_SYMBOL}" || true)
  if [[ ${symbol_count} -ge 1 ]]; then
    echo "    PASS: '${VERIFY_SYMBOL}' appears ${symbol_count}x in binary"
  else
    echo "    FAIL: '${VERIFY_SYMBOL}' NOT found in binary." >&2
    echo "          Build completed but the fork's code is missing." >&2
    echo "          DO NOT test this DMG." >&2
    exit 2
  fi

  # 2. Occurrence count in staged source (for cross-reference)
  # Counts across the whole staged tree; compiler deduplication means binary
  # count is always ≤ source count, but non-zero source + non-zero binary
  # confirms the source-to-binary path is intact.
  source_count=$(/usr/bin/grep -rc -- "${VERIFY_SYMBOL}" "${FORK_BUILD_DIR}/src" 2>/dev/null \
    | awk -F: '{s+=$2} END {print s+0}')
  echo "    INFO: source tree had ${source_count} references; binary has ${symbol_count} (compiler may dedup)"
  if [[ ${source_count} -eq 0 ]]; then
    echo "    FAIL: staged source has ZERO references to '${VERIFY_SYMBOL}'." >&2
    echo "          The rsync may have excluded the modified files, or the worktree is" >&2
    echo "          missing the patch. DO NOT test this DMG." >&2
    exit 2
  fi
fi

# --- Post-build verification (informational; warnings don't fail the build) ---
echo ""
echo "==> Running post-build verification..."
VERIFY_ISSUES=0

# 1. Architecture
arch_errors=0
arch_checked=0
while IFS= read -r -d '' b; do
  info=$(file "${b}" 2>/dev/null || true)
  [[ "${info}" == *"Mach-O"* ]] || continue
  arch_checked=$((arch_checked + 1))
  if [[ "${info}" != *"${MACHINE_ARCH}"* ]]; then
    echo "    FAIL: wrong arch in ${b:t}"
    arch_errors=$((arch_errors + 1))
  fi
done < <(/usr/bin/find "${APP_BUNDLE}/Contents/MacOS" \( -name "*.dylib" -o -type f -perm +111 \) -not -type d -print0 2>/dev/null)
if [[ ${arch_errors} -eq 0 ]] && [[ ${arch_checked} -gt 0 ]]; then
  echo "    PASS: all ${arch_checked} binaries/dylibs are ${MACHINE_ARCH}"
elif [[ ${arch_errors} -gt 0 ]]; then
  VERIFY_ISSUES=$((VERIFY_ISSUES + arch_errors))
fi

# 2. Size sanity (fork builds may differ from production, so wider range)
app_bytes=$(/usr/bin/find "${APP_BUNDLE}" -type f -exec /usr/bin/stat -f '%z' {} + 2>/dev/null | awk '{s+=$1} END {print s}')
size_mb=$(echo "${app_bytes:-0}" | awk '{printf "%.1f", $1/1000/1000}')
if (( $(echo "${size_mb} < 50" | bc -l) )) || (( $(echo "${size_mb} > 150" | bc -l) )); then
  echo "    WARN: App size ${size_mb} MB outside typical 50-150 MB range"
  VERIFY_ISSUES=$((VERIFY_ISSUES + 1))
else
  echo "    PASS: App size ${size_mb} MB"
fi

# 3. Homebrew leak
leak_found=false
for lib in "${APP_BUNDLE}/Contents/MacOS/libs/"*.dylib "${BINARY}"; do
  [[ -f "${lib}" ]] || continue
  leaks=$(otool -L "${lib}" 2>/dev/null | grep -E "/opt/homebrew|/usr/local/opt" || true)
  if [[ -n "${leaks}" ]]; then
    echo "    WARN: Homebrew reference in ${lib:t}:"
    echo "${leaks}" | while read -r line; do echo "      ${line}"; done
    leak_found=true
  fi
done
if ! ${leak_found}; then
  echo "    PASS: no Homebrew/external library references"
else
  VERIFY_ISSUES=$((VERIFY_ISSUES + 1))
fi

# 4. Qt version in binary (informational)
BUILT_QT=$(otool -L "${BINARY}" 2>/dev/null | grep libQt6Core | sed 's/.*current version \([0-9.]*\).*/\1/' | head -1 || true)
if [[ -n "${BUILT_QT}" ]]; then
  echo "    INFO: Qt version linked into binary: ${BUILT_QT}"
fi

# 5. Distinct Qt versions bundled in libs/ — must be exactly 1. More than 1
# indicates the restore step extracted overlapping versions (the Fix 2 bug).
if [[ -d "${APP_BUNDLE}/Contents/MacOS/libs" ]]; then
  qt_versions=$(/usr/bin/find "${APP_BUNDLE}/Contents/MacOS/libs" -name 'libQt6Core.*.dylib' \
    -not -type l 2>/dev/null \
    | /usr/bin/sed -E 's/.*libQt6Core\.([0-9.]+)\.dylib/\1/' \
    | /usr/bin/sort -u)
  qt_version_count=$(echo "${qt_versions}" | /usr/bin/grep -c . || true)
  if [[ ${qt_version_count} -eq 1 ]]; then
    echo "    PASS: exactly 1 Qt version bundled (${qt_versions})"
  elif [[ ${qt_version_count} -gt 1 ]]; then
    echo "    FAIL: multiple Qt versions bundled — DMG is bloated / linking ambiguous:"
    echo "${qt_versions}" | while read -r v; do echo "      - ${v}"; done
    VERIFY_ISSUES=$((VERIFY_ISSUES + 1))
  else
    echo "    WARN: no libQt6Core dylib bundled (unexpected)"
    VERIFY_ISSUES=$((VERIFY_ISSUES + 1))
  fi
fi

# 6. Report bundled libs inventory for at-a-glance sanity
if [[ -d "${APP_BUNDLE}/Contents/MacOS/libs" ]]; then
  echo "    --- bundled libs ---"
  /usr/bin/find "${APP_BUNDLE}/Contents/MacOS/libs" -name '*.dylib' -not -type l 2>/dev/null \
    | while read -r l; do echo "    $(basename "${l}")"; done
fi

# --- Counter commit + DMG naming ---
# BUILD_NUM was predicted up-front (stable across retries); commit it now that
# the build succeeded. Previous value stays unchanged on any failure.
BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

echo "${BUILD_NUM}" > "${BUILD_COUNTER_FILE}.tmp" && command mv "${BUILD_COUNTER_FILE}.tmp" "${BUILD_COUNTER_FILE}"

DMG_FINAL_NAME="MKVToolNix-${MTX_VER}-${ARCH_LABEL}-${BUILD_LABEL}-fork-${SLUG}-${BUILD_HASH}.dmg"
command cp "${DMG_PATH}" "${BUILD_DIR}/${DMG_FINAL_NAME}"
(cd "${BUILD_DIR}" && shasum -a 256 "${DMG_FINAL_NAME}" > "${DMG_FINAL_NAME}.sha256")

# --- Summary ---
elapsed=$SECONDS
mins=$((elapsed / 60))
secs=$((elapsed % 60))

echo ""
echo "==> DONE in ${mins}m $(printf '%02d' ${secs})s."
echo ""
echo "  DMG:          ${BUILD_DIR}/${DMG_FINAL_NAME}"
echo "  SHA256:       ${BUILD_DIR}/${DMG_FINAL_NAME}.sha256"
echo "  Log:          ${LOG_FILE}"
echo "  Build number: ${BUILD_NUM} (${ARCH_LABEL}/fork)"
echo "  Build hash:   ${BUILD_HASH}"
echo "  VERSIONNAME:  ${VERSIONNAME}  (shown as \"v${MTX_VER} ('${VERSIONNAME}')\" in the About dialog)"
echo ""
echo "  Verification:"
if [[ -n "${VERIFY_SYMBOL}" ]]; then
  echo "    ${VERIFY_SYMBOL}: PRESENT (fork code compiled in)"
fi
echo "    Architecture: ${arch_errors} failures / ${arch_checked} checked"
echo "    App size:     ${size_mb} MB"
echo "    Homebrew leaks: $(${leak_found} && echo 'DETECTED (review log)' || echo 'none')"
if [[ -n "${BUILT_QT}" ]]; then
  echo "    Qt version:   ${BUILT_QT}"
fi
if [[ ${VERIFY_ISSUES} -gt 0 ]]; then
  echo "    Issues to review: ${VERIFY_ISSUES} (non-fatal)"
fi
echo ""
echo "To install and test:"
echo "    open \"${BUILD_DIR}/${DMG_FINAL_NAME}\""
echo "    cp -R \"/Volumes/MKVToolNix-${MTX_VER}/MKVToolNix-${MTX_VER}.app\" /Applications/"
echo "    hdiutil detach \"/Volumes/MKVToolNix-${MTX_VER}\""
echo ""
echo "NOTE: This DMG is a fork/experimental build — NOT a release. release/ was not touched."
