#!/bin/bash
set -e

# Update package lists and install packages based on available package manager

if command -v apt-get >/dev/null; then
    echo "Detected apt-get. Installing via apt-get..."
    sudo apt-get update
    sudo apt-get install -y sccache ccache cppcheck iwyu lcov binutils graphviz doxygen llvm valgrind

    # for debian packaging
    sudo apt-get install -y dpkg-dev fakeroot binutils

    # Ensure pip is available
    sudo apt-get install -y python3-pip

    # Install latest CMake from Kitware APT repository
    # Determine codename (e.g. focal, jammy). Fall back to 'noble' if lsb_release isn't available.
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
    echo "Installing latest CMake via Kitware repo for codename: ${CODENAME}"

    # Purge older distro cmake if present (ignore errors)
    sudo apt-get purge --auto-remove -y cmake || true

    # Ensure required tools for adding the repo are present
    sudo apt-get update
    sudo apt-get install -y wget gpg lsb-release ca-certificates

    # Add Kitware GPG key (dearmored) and repository
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc \
      | gpg --dearmor \
      | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${CODENAME} main" \
      | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null

    sudo apt-get update
    sudo apt-get install -y cmake

    cmake --version

    # desired tool versions
    LLVM_WANTED=21        # for the apt.llvm.org helper (llvm.sh)
    CLANG_WANTED=21       # for update-alternatives clang/clang++=21
    export DEBIAN_FRONTEND=noninteractive
    APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    
    # minimal prerequisites
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends wget gnupg lsb-release ca-certificates

    # Add the LLVM apt repo using the official helper (non-interactive)
    wget -qO- https://apt.llvm.org/llvm.sh | sudo bash -s -- "${LLVM_WANTED}" all

    sudo apt-get update

    # clang
    if [ -x "/usr/bin/clang-${CLANG_WANTED}" ]; then
      sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-"${CLANG_WANTED}" 100
      sudo update-alternatives --set clang /usr/bin/clang-"${CLANG_WANTED}"
    fi

    # clang++
    if [ -x "/usr/bin/clang++-${CLANG_WANTED}" ]; then
      sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-"${CLANG_WANTED}" 100
      sudo update-alternatives --set clang++ /usr/bin/clang++-"${CLANG_WANTED}"
    fi

    # clang-tidy
    if [ -x "/usr/bin/clang-tidy-${CLANG_WANTED}" ]; then
      sudo update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-"${CLANG_WANTED}" 100
    fi

    # clang-format
    if [ -x "/usr/bin/clang-format-${CLANG_WANTED}" ]; then
      sudo update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-"${CLANG_WANTED}" 100
    fi

    # Verify
    clang --version
    clang++ --version

    GCC_WANTED="${GCC_WANTED:-15}"   # change to 13, 15, ... or export before running
    TRY_PPA="${TRY_PPA:-yes}"        # set to "no" to skip adding the ubuntu-toolchain PPA
    NONINTERACTIVE="${NONINTERACTIVE:-1}"  # set to 0 if you want interactive apt prompts

    export DEBIAN_FRONTEND=$([ "$NONINTERACTIVE" -eq 1 ] && echo noninteractive || echo dialog)

    PKGS=( "gcc-${GCC_WANTED}" "g++-${GCC_WANTED}" "gfortran-${GCC_WANTED}" )

    echo "=== Installing GCC ${GCC_WANTED} (packages: ${PKGS[*]}) ==="
    sudo apt-get update -y || true

    # helper: attempt apt install and return 0/1
    _try_install_via_apt() {
      echo "--- apt-get install attempt ---"
      sudo apt-get install -y --no-install-recommends "${PKGS[@]}" && return 0 || return 1
    }

    # Preconditions: ensure add-apt-repository is available (needed if we add PPA)
    ensure_apt_helpers() {
      if ! command -v add-apt-repository >/dev/null 2>&1; then
        echo "Installing apt helper packages (software-properties-common, ca-certificates)..."
        sudo apt-get update
    sudosudo apt-get install -y --no-install-recommends software-properties-common ca-certificates apt-transport-https gnupg
      fi
    }

    # 1) Try to install from enabled system repos first
    if _try_install_via_apt; then
      echo "Installed ${PKGS[*]} from system repos."
    else
      echo "Packages not available in current apt repos."
      if [ "$TRY_PPA" = "yes" ]; then
        echo "Attempting to add ubuntu-toolchain-r/test PPA and retry..."
        ensure_apt_helpers
        # Add the PPA (idempotent)
        # Note: for production systems be cautious; PPA may not have builds for every Ubuntu codename.
        sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
        sudo apt-get update
        if _try_install_via_apt; then
          echo "Installed ${PKGS[*]} from ubuntu-toolchain-r/test PPA."
        else
          echo "Still couldn't install ${PKGS[*]} after adding PPA."
          echo "Falling back to alternate suggestions below."
          INSTALL_FAILED=1
        fi
      else
        echo "Skipping PPA step (TRY_PPA=no)."
        INSTALL_FAILED=1
      fi
    fi

    # If installation failed, show fallbacks and exit non-zero
    if [ "${INSTALL_FAILED:-0}" = "1" ]; then
      cat <<EOF

Could not install gcc-${GCC_WANTED} from apt. Fallback options:
  * Use conda/mamba: `mamba install -n myenv -c conda-forge gcc= ${GCC_WANTED} gxx=${GCC_WANTED}`
  * Use Docker: `docker run --rm -it gcc:${GCC_WANTED} bash`
  * Build GCC from source (slow)
  * Verify your Ubuntu codename (lsb_release -c) and whether the PPA supplies packages for it.

If you want, re-run this script with TRY_PPA=no to skip PPA, or set GCC_WANTED to a version that exists on your distro.

EOF
      exit 2
    fi

    # 2) Register update-alternatives for the binaries we care about
    echo "=== Configuring update-alternatives for GCC ${GCC_WANTED} ==="

    cmd_add_alt() {
      local name="$1" target="$2" priority="${3:-100}"
      if [ -x "$target" ]; then
        sudo update-alternatives --install "/usr/bin/${name}" "${name}" "${target}" "${priority}" >/dev/null 2>&1 || true
        sudo update-alternatives --set "${name}" "${target}" >/dev/null 2>&1 || true
        echo " -> set ${name} -> ${target}"
      else
        echo " -> ${target} not found, skipping ${name}"
      fi
    }

    # common binary names and their installed paths
    cmd_add_alt gcc "/usr/bin/gcc-${GCC_WANTED}"
    cmd_add_alt g++ "/usr/bin/g++-${GCC_WANTED}"
    cmd_add_alt gcov "/usr/bin/gcov-${GCC_WANTED}"
    # also cover cc/c++ aliases
    if [ -x "/usr/bin/gcc-${GCC_WANTED}" ]; then
      sudo ln -sf "/usr/bin/gcc-${GCC_WANTED}" /usr/bin/cc || true
    fi
    if [ -x "/usr/bin/g++-${GCC_WANTED}" ]; then
      sudo ln -sf "/usr/bin/g++-${GCC_WANTED}" /usr/bin/c++ || true
    fi

    # 3) verify
    echo "=== Verification ==="
    echo "gcc -> $(which gcc 2>/dev/null || echo not-found) : $(gcc --version 2>/dev/null || true)"
    echo "g++ -> $(which g++ 2>/dev/null || echo not-found) : $(g++ --version 2>/dev/null || true)"
    if command -v gfortran >/dev/null 2>&1; then
      echo "gfortran -> $(gfortran --version | head -n1)"
    fi

    # 4) export CC/CXX for current shell session
    if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
      export CC="$(which gcc)"
      export CXX="$(which g++)"
      echo "Exported CC=${CC} and CXX=${CXX} for this shell."
      echo "To make these persistent in scripts/CI, add: export CC=$(which gcc); export CXX=$(which g++)"
    fi

    echo "Done. If you need me to print the apt policy or lsb_release -a output to debug further, say so."

    
elif command -v yum >/dev/null; then
    echo "Detected yum. Installing via yum..."
    sudo yum install -y sccache ccache cppcheck iwyu lcov binutils graphviz doxygen llvm cmake
    # ensure pip exists
    sudo yum install -y python3-pip

elif command -v dnf >/dev/null; then
    echo "Detected dnf. Installing via dnf..."
    sudo dnf install -y sccache ccache cppcheck iwyu lcov binutils graphviz doxygen llvm cmake
    # ensure pip exists
    sudo dnf install -y python3-pip

elif command -v pacman >/dev/null; then
    echo "Detected pacman. Installing via pacman..."
    sudo pacman -Sy --noconfirm sccache ccache cppcheck iwyu lcov binutils graphviz doxygen llvm cmake
    # ensure pip exists
    sudo pacman -Sy --noconfirm python-pip

else
    echo "No supported package manager found. Please install ccache, cppcheck, cmake and python3-pip/pip manually."
    exit 1
fi

# Show gcov presence/version (non-fatal)
echo "Checking for gcov..."
gcov --version || true
which gcov || true

# Install gcovr via pip (try pip3, fall back to pip). Use --user to avoid permission issues.
echo "Installing gcovr (Python tool for coverage reports)..."
if command -v pip3 >/dev/null; then
    pip3 install --upgrade --user gcovr
elif command -v pip >/dev/null; then
    pip install --upgrade --user gcovr
else
    echo "pip not found. You may need to install python3-pip / pip before installing gcovr."
fi

echo "Installation complete."
