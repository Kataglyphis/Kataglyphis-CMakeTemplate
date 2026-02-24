#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SELF_DIR}/lib/common.sh"
init_repo_context

BUILD_RELEASE_DIR="build-release"
CLANG_RELEASE_PRESET="linux-release-clang"
DO_CALLGRIND=0
DO_APPIMAGE=1
APPIMAGE_OUT_DIR=""
LOCAL_APPIMAGETOOL_PATH=""
DO_FLATPAK=1
FLATPAK_EXPLICIT=0
FLATPAK_OUT_DIR=""
FLATPAK_RUNTIME="${FLATPAK_RUNTIME:-org.freedesktop.Platform}"
FLATPAK_RUNTIME_VERSION="${FLATPAK_RUNTIME_VERSION:-24.08}"
FLATPAK_SDK="${FLATPAK_SDK:-org.freedesktop.Sdk}"
FLATPAK_BRANCH="${FLATPAK_BRANCH:-master}"
AUTO_INSTALL_FLATPAK="${AUTO_INSTALL_FLATPAK:-1}"

usage() {
  cat <<'EOF'
Usage: release_package_callgrind.sh [options]

Options:
  --build-release-dir <dir>       Build directory (default: build-release)
  --clang-release-preset <name>   CMake preset (default: linux-release-clang)
  --callgrind                     Run valgrind/callgrind after packaging (default: off)
  --appimage                      Build an AppImage from the install tree (default: on)
  --no-appimage                   Disable AppImage build
  --appimage-out-dir <dir>        Output directory for the AppImage (default: build dir)
  --flatpak|--flatpack            Build a Flatpak bundle from the install tree (default: on)
  --no-flatpak|--no-flatpack      Disable Flatpak build
  --flatpak-out-dir <dir>         Output directory for the Flatpak bundle (default: build dir)
  -h, --help                      Show this help

Environment:
  APPIMAGETOOL=<path>             Override appimagetool binary (default: appimagetool)
  FLATPAK_RUNTIME=<name>          Flatpak runtime (default: org.freedesktop.Platform)
  FLATPAK_RUNTIME_VERSION=<ver>   Flatpak runtime version (default: 24.08)
  FLATPAK_SDK=<name>              Flatpak SDK (default: org.freedesktop.Sdk)
  AUTO_INSTALL_FLATPAK=0|1        Auto-install flatpak tools via apt if missing (default: 1)
EOF
}

ensure_appimagetool() {
  if [[ -n "${APPIMAGETOOL:-}" ]]; then
    require_cmd "${APPIMAGETOOL}"
    echo "${APPIMAGETOOL}"
    return 0
  fi

  if command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool"
    return 0
  fi

  local arch
  arch="$(normalize_arch)"

  local appimagetool_name=""
  case "${arch}" in
    x86_64) appimagetool_name="appimagetool-x86_64.AppImage" ;;
    aarch64) appimagetool_name="appimagetool-aarch64.AppImage" ;;
    *)
      echo "Unsupported architecture for automatic appimagetool download: ${arch}" >&2
      return 1
      ;;
  esac

  LOCAL_APPIMAGETOOL_PATH="${REPO_ROOT}/${appimagetool_name}"
  if [[ ! -x "${LOCAL_APPIMAGETOOL_PATH}" ]]; then
    require_cmd wget
    echo "appimagetool not found in PATH. Downloading ${appimagetool_name} ..." >&2
    wget -O "${LOCAL_APPIMAGETOOL_PATH}" "https://github.com/AppImage/AppImageKit/releases/download/continuous/${appimagetool_name}"
    chmod +x "${LOCAL_APPIMAGETOOL_PATH}"
  fi

  echo "${LOCAL_APPIMAGETOOL_PATH}"
}

require_cmd() {
  local cmd="$1"
  if [[ "${cmd}" == */* ]]; then
    if [[ ! -x "${cmd}" ]]; then
      echo "Missing required executable: ${cmd}" >&2
      return 1
    fi
    return 0
  fi

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    return 1
  fi
}

normalize_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "${arch}" ;;
  esac
}

read_cache_var() {
  local cache_file="$1"
  local key="$2"
  local line
  line="$(grep -E "^${key}:[^=]*=" "${cache_file}" 2>/dev/null | head -n 1 || true)"
  if [[ -n "${line}" ]]; then
    echo "${line#*=}"
  fi
}

build_appimage() {
  local build_dir="$1"
  local out_dir="$2"

  local appimagetool
  appimagetool="$(ensure_appimagetool)"
  require_cmd "${appimagetool}"
  require_cmd mksquashfs

  local cache_file="${build_dir}/CMakeCache.txt"
  local project_name="KataglyphisCppProject"
  local project_version=""
  if [[ -f "${cache_file}" ]]; then
    project_name="$(read_cache_var "${cache_file}" CMAKE_PROJECT_NAME || true)"
    project_version="$(read_cache_var "${cache_file}" CMAKE_PROJECT_VERSION || true)"
  fi
  if [[ -z "${project_name}" ]]; then
    project_name="KataglyphisCppProject"
  fi

  local arch
  arch="$(normalize_arch)"

  local git_sha=""
  git_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"

  local version_suffix=""
  if [[ -n "${project_version}" ]]; then
    version_suffix="${project_version}"
  elif [[ -n "${git_sha}" ]]; then
    version_suffix="${git_sha}"
  else
    version_suffix="unknown"
  fi

  local appdir="${build_dir}/AppDir"
  rm -rf "${appdir}"
  mkdir -p "${appdir}"

  cmake --install "${build_dir}" --prefix "${appdir}/usr"

  if [[ ! -x "${appdir}/usr/bin/${project_name}" ]]; then
    echo "AppImage staging failed: expected executable at ${appdir}/usr/bin/${project_name}" >&2
    return 1
  fi

  cat >"${appdir}/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec "\${HERE}/usr/bin/${project_name}" "\$@"
EOF
  chmod +x "${appdir}/AppRun"

  # Minimal desktop entry + icon so appimagetool recognizes the AppDir
  cat >"${appdir}/${project_name}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${project_name}
Exec=${project_name}
Icon=${project_name}
Categories=Utility;
Terminal=true
EOF

  if [[ -f "${REPO_ROOT}/images/logo.png" ]]; then
    cp "${REPO_ROOT}/images/logo.png" "${appdir}/${project_name}.png"
  elif [[ -f "${REPO_ROOT}/images/Engine_logo.png" ]]; then
    cp "${REPO_ROOT}/images/Engine_logo.png" "${appdir}/${project_name}.png"
  fi

  mkdir -p "${out_dir}"
  local out_name="${project_name}-${version_suffix}-linux-${arch}.AppImage"

  local -a appimagetool_cmd
  if [[ "${appimagetool}" == *.AppImage ]]; then
    appimagetool_cmd=("${appimagetool}" --appimage-extract-and-run)
  else
    appimagetool_cmd=("${appimagetool}")
  fi

  ARCH="${arch}" "${appimagetool_cmd[@]}" "${appdir}" "${out_dir}/${out_name}"
  echo "AppImage written: ${out_dir}/${out_name}"
}

sanitize_for_app_id() {
  local value="$1"
  value="${value//[^a-zA-Z0-9]/-}"
  value="${value#-}"
  value="${value%-}"
  if [[ -z "${value}" ]]; then
    value="KataglyphisCppProject"
  fi
  echo "${value}"
}

build_flatpak() {
  local build_dir="$1"
  local out_dir="$2"

  require_cmd flatpak-builder
  require_cmd flatpak

  local cache_file="${build_dir}/CMakeCache.txt"
  local project_name="KataglyphisCppProject"
  local project_version=""
  if [[ -f "${cache_file}" ]]; then
    project_name="$(read_cache_var "${cache_file}" CMAKE_PROJECT_NAME || true)"
    project_version="$(read_cache_var "${cache_file}" CMAKE_PROJECT_VERSION || true)"
  fi
  if [[ -z "${project_name}" ]]; then
    project_name="KataglyphisCppProject"
  fi

  local git_sha=""
  git_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"

  local version_suffix=""
  if [[ -n "${project_version}" ]]; then
    version_suffix="${project_version}"
  elif [[ -n "${git_sha}" ]]; then
    version_suffix="${git_sha}"
  else
    version_suffix="unknown"
  fi

  local app_id="org.kataglyphis.$(sanitize_for_app_id "${project_name}")"
  local flatpak_root="${build_dir}/flatpak"
  local source_dir="${flatpak_root}/source"
  local build_root="${flatpak_root}/build"
  local repo_dir="${flatpak_root}/repo"
  local manifest_path="${flatpak_root}/${app_id}.json"

  rm -rf "${flatpak_root}"
  mkdir -p "${source_dir}/app" "${build_root}" "${repo_dir}" "${out_dir}"

  cmake --install "${build_dir}" --prefix "${source_dir}/app"

  local source_app_path
  source_app_path="$(cd "${source_dir}/app" && pwd)"

  if [[ ! -x "${source_dir}/app/bin/${project_name}" ]]; then
    echo "Flatpak staging failed: expected executable at ${source_dir}/app/bin/${project_name}" >&2
    return 1
  fi

  cat >"${manifest_path}" <<EOF
{
  "app-id": "${app_id}",
  "runtime": "${FLATPAK_RUNTIME}",
  "runtime-version": "${FLATPAK_RUNTIME_VERSION}",
  "sdk": "${FLATPAK_SDK}",
  "command": "${project_name}",
  "modules": [
    {
      "name": "${project_name}",
      "buildsystem": "simple",
      "build-commands": [
        "cp -a . /app"
      ],
      "sources": [
        {
          "type": "dir",
          "path": "${source_app_path}"
        }
      ]
    }
  ]
}
EOF

  flatpak-builder --disable-rofiles-fuse --force-clean --repo="${repo_dir}" "${build_root}" "${manifest_path}"

  local out_name="${project_name}-${version_suffix}-linux.flatpak"
  flatpak build-bundle "${repo_dir}" "${out_dir}/${out_name}" "${app_id}" "${FLATPAK_BRANCH}"
  echo "Flatpak bundle written: ${out_dir}/${out_name}"
}

ensure_flatpak_tools() {
  local -a missing_cmds=()
  if ! command -v flatpak-builder >/dev/null 2>&1; then
    missing_cmds+=("flatpak-builder")
  fi
  if ! command -v flatpak >/dev/null 2>&1; then
    missing_cmds+=("flatpak")
  fi

  if [[ "${#missing_cmds[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${AUTO_INSTALL_FLATPAK}" != "1" ]]; then
    echo "Missing required command(s): ${missing_cmds[*]}" >&2
    return 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Missing required command(s): ${missing_cmds[*]}" >&2
    echo "Automatic install is only supported with apt-get." >&2
    return 1
  fi

  echo "Missing Flatpak tools (${missing_cmds[*]}). Trying automatic installation via apt..." >&2

  if [[ "${EUID}" -eq 0 ]]; then
    apt-get update
    apt-get install -y flatpak flatpak-builder
  else
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo is required for automatic installation but was not found." >&2
      return 1
    fi
    sudo apt-get update
    sudo apt-get install -y flatpak flatpak-builder
  fi

  if ! command -v flatpak-builder >/dev/null 2>&1 || ! command -v flatpak >/dev/null 2>&1; then
    echo "Automatic Flatpak tool installation failed." >&2
    return 1
  fi

  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-release-dir)
      BUILD_RELEASE_DIR="$2"
      shift 2
      ;;
    --clang-release-preset)
      CLANG_RELEASE_PRESET="$2"
      shift 2
      ;;
    --callgrind)
      DO_CALLGRIND=1
      shift 1
      ;;
    --appimage)
      DO_APPIMAGE=1
      shift 1
      ;;
    --no-appimage)
      DO_APPIMAGE=0
      shift 1
      ;;
    --appimage-out-dir)
      APPIMAGE_OUT_DIR="$2"
      shift 2
      ;;
    --flatpak|--flatpack)
      DO_FLATPAK=1
      FLATPAK_EXPLICIT=1
      shift 1
      ;;
    --no-flatpak|--no-flatpack)
      DO_FLATPAK=0
      shift 1
      ;;
    --flatpak-out-dir)
      FLATPAK_OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

CMAKE_EXTRA_ARGS=()
append_default_toolchain_args CMAKE_EXTRA_ARGS

cmake -B "${BUILD_RELEASE_DIR}" --preset "${CLANG_RELEASE_PRESET}" "${CMAKE_EXTRA_ARGS[@]}"
cmake --build "${BUILD_RELEASE_DIR}" --preset "${CLANG_RELEASE_PRESET}"
cmake --build "${BUILD_RELEASE_DIR}" --target package

if [[ "${DO_FLATPAK}" -eq 1 ]]; then
  if [[ -z "${FLATPAK_OUT_DIR}" ]]; then
    FLATPAK_OUT_DIR="${BUILD_RELEASE_DIR}"
  fi
  if ! ensure_flatpak_tools; then
    if [[ "${FLATPAK_EXPLICIT}" -eq 1 ]]; then
      echo "Flatpak requested but required tools are unavailable." >&2
      exit 1
    fi
    echo "Skipping Flatpak build (required tools are unavailable)." >&2
    echo "Install flatpak + flatpak-builder or run with --no-flatpak to suppress this warning." >&2
  else
    build_flatpak "${BUILD_RELEASE_DIR}" "${FLATPAK_OUT_DIR}"
  fi
fi

if [[ "${DO_CALLGRIND}" -eq 1 ]]; then
  require_cmd valgrind
  (
    cd "${BUILD_RELEASE_DIR}"
    valgrind --tool=callgrind ./KataglyphisCppProject
  )
fi
