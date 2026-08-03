#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
README_FILE=$(find "$(dirname "$KERNEL_DIR")" -name "README_Kernel.txt" -print -quit 2>/dev/null || echo "")
if [ -z "$README_FILE" ]; then
 echo "[-] Error: It is necessary to follow README from SAMSUNG (README_Kernel.txt not found)" >&2
 exit 1
fi
if [ ! -f "$KERNEL_DIR/build_kernel.sh" ]; then
 echo "Error: Build script is necessary from SAMSUNG (build_kernel.sh not found)." >&2
 exit 1
fi

VERSION=$(grep -w '^VERSION' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
PATCHLEVEL=$(grep -w '^PATCHLEVEL' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
KERNEL_VERSION="${VERSION}.${PATCHLEVEL}"
REPO_URL="https://raw.githubusercontent.com/Tam97123/Build-Kernel_scripts/refs/heads/main"
TOOLCHAIN_DIR="$KERNEL_DIR/toolchain"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
DEFCONFIG_DIR=(
    "$KERNEL_DIR/arch/arm64/configs"
    "$KERNEL_DIR/arch/arm/configs"
)
GCC64=false
GCC32=false
# Hardcode this variable if you dont want prompt
CUSTOM_DEFCONFIG=

get_script() {
 local script_name="$1"
 echo "[+] Downloading $script_name..."
  if ! curl -sLO "$REPO_URL/scripts/$script_name"; then
   echo "[-] Error: Can not download $script_name!" >&2
   exit 1
  fi
  source "$script_name"
  rm -f "$script_name"
}

# ==============================================================================
# 1. DEPENDENCIES & OS CHECK
# ==============================================================================
install_dependencies () {
    echo "================================================="
    echo "[+] Detecting OS and installing dependencies..."
    if command -v apt &> /dev/null; then
     echo "[+] Ubuntu/Debian-based system detected, using apt..."
     sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
      default-jdk gnupg flex bison gperf build-essential zip curl ccache libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
      make sudo bc grep tofrodos python3-markdown libxml2-utils xsltproc libtinfo6 \
      repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd libyaml-dev --fix-missing  
     wget -q http://mirrors.kernel.org/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.2_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.2_amd64.deb && rm -f libtinfo5_6.3-2ubuntu0.2_amd64.deb
    elif command -v dnf &> /dev/null; then
     echo "[+] Fedora/RHEL-based system detected, using dnf..."
     sudo dnf group install -y "c-development" "development-tools"
     sudo dnf install -y dtc lz4 xz zlib-devel java-latest-openjdk-devel python3 \
      p7zip p7zip-plugins android-tools erofs-utils \
      ncurses-devel ccache libX11-devel readline-devel mesa-libGL-devel python3-markdown \
      libxml2 libxslt dos2unix kmod openssl elfutils-libelf-devel dwarves \
      openssl-devel libarchive zstd rsync libyaml-devel openssl-devel-engine --skip-unavailable
    else
     echo "[-] Error: Can not determine package manager, please install dependencies manually." >&2
     exit 1
    fi
    touch .requirements
}

if [ ! -f ".requirements" ]; then install_dependencies; fi

# ==============================================================================
# 2. CHECK KERNEL VERSION
# ==============================================================================
if [ -z "$VERSION" ] || [ -z "$PATCHLEVEL" ]; then
 echo "[-] Error: Can not detect kernel version!" >&2
 exit 1
elif [[ ( "$VERSION" -eq "5" && "$PATCHLEVEL" -gt "4" ) || "$VERSION" -gt "5" ]]; then
 echo "[-] Not supporting GKI kernel ${KERNEL_VERSION}!"
 exit 1
else
 echo "[+] Detected kernel ${KERNEL_VERSION}!"
fi

# ==============================================================================
# 3. README FROM SAMSUNG
# ==============================================================================
extract_toolchain_path() {
    local toolchain="$1"

    if grep -q "$toolchain" "$README_FILE"; then
     local toolchain_line
     toolchain_line=$(grep -m 1 "${toolchain}=/usr/local" "$README_FILE" || true)    
     if [ -z "$toolchain_line" ]; then
      return 0
     fi

     local toolchain_path
     toolchain_path=$(echo "$toolchain_line" | sed -n "s/.*${toolchain}=\/usr\/local\([^ ]*\).*/\1/p")
     export "$toolchain"="$toolchain_path"
    fi
}

extract_toolchain_path "CC"
extract_toolchain_path "CROSS_COMPILE"
extract_toolchain_path "CROSS_COMPILE_ARM32"
extract_toolchain_path "CLANG_TRIPLE"

# ==============================================================================
# 4. CHECK DEFCONFIG
# ==============================================================================
validate_defconfigs() {
    local input_configs="$1"
    local valid_names=""
    local valid_paths=""

    for config in $input_configs; do
     local config_paths=$(find "${DEFCONFIG_DIR[@]}" -type f -name "$config" -print -quit 2>/dev/null)
     if [ -n "$config_paths" ]; then
      valid_names="$valid_names $(basename "$config_paths")"
      valid_paths="$valid_paths $config_paths"
     else
      echo "[-] Error: No such defconfig name '$config'" >&2
      return 1
     fi
    done
    VALID_DEFCONFIG_NAMES="${valid_names# }"
    VALID_DEFCONFIG_PATHS="${valid_paths# }"
    return 0
}

DEFCONFIG=$(grep -oE '[a-zA-Z0-9_-]+_defconfig' "$README_FILE" 2>/dev/null | head -n 1)
if [ -z "$DEFCONFIG" ]; then
 echo "[-] Error: Could not find defconfig to use in README." >&2
 exit 1
fi

if ! validate_defconfigs "$DEFCONFIG"; then
 echo "[-] Error: Can not find '$DEFCONFIG' in kernel source tree" >&2
 exit 1
else
 DEFCONFIG="$VALID_DEFCONFIG_NAMES"
 DEFCONFIG_PATHS="$VALID_DEFCONFIG_PATHS"
 echo "[+] Using '$DEFCONFIG' as defconfig"
fi

if [ -z "$CUSTOM_DEFCONFIG" ]; then
 while true; do
  read -p "Enter custom defconfig (supports multiple, space-separated): " user_input
   if [ -z "$user_input" ]; then
    echo -e "\nYou do not use custom defconfig"
    break
   fi
   if validate_defconfigs "$user_input"; then
    CUSTOM_DEFCONFIG="$VALID_DEFCONFIG_NAMES"
    DEFCONFIG_PATHS="$DEFCONFIG_PATHS $VALID_DEFCONFIG_PATHS"
    break
  fi
 done
else
 if ! validate_defconfigs "$CUSTOM_DEFCONFIG"; then exit 1; fi
 CUSTOM_DEFCONFIG="$VALID_DEFCONFIG_NAMES"
 DEFCONFIG_PATHS="$DEFCONFIG_PATHS $VALID_DEFCONFIG_PATHS"
fi
echo "[+] Using '$CUSTOM_DEFCONFIG' as custom defconfig"

# ==============================================================================
# 5. DETECT ARCHITECTURE
# ==============================================================================
check_flag() {
    local flag="$1"
    for path in $DEFCONFIG_PATHS; do
     if grep -q "$flag" "$path" 2>/dev/null; then return 0; fi
    done
    return 1
}

README_ARCH=$(grep -E '^export ARCH=' "$KERNEL_DIR/build_kernel.sh" | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || echo "")

if [ -n "$README_ARCH" ]; then
 export ARCH="$README_ARCH"
 if [ "$ARCH" = "arm64" ]; then
  export CLANG_TRIPLE="aarch64-linux-gnu-"
   if [[ "$VERSION" -eq "4" && "$PATCHLEVEL" -le "14" ]]; then GCC64=true; fi
   if check_flag "CONFIG_COMPAT_VDSO=y"; then GCC32=true; fi
  else
   export CLANG_TRIPLE="arm-linux-gnueabi-"
   GCC64=false
   GCC32=true
  fi
else
 if check_flag "CONFIG_ARM64=y"; then
  export ARCH=arm64
  export CLANG_TRIPLE="aarch64-linux-gnu-"
  if [[ "$VERSION" -eq "4" && "$PATCHLEVEL" -le "14" ]]; then GCC64=true; fi
  if check_flag "CONFIG_COMPAT_VDSO=y"; then GCC32=true; fi
 else
  export ARCH=arm
  export CLANG_TRIPLE="arm-linux-gnueabi-"
  GCC64=false
  GCC32=true
 fi
fi

# ==============================================================================
# 6. DOWNLOAD TOOLCHAIN
# ==============================================================================
# Download clang
if [ -n "${CC:-}" ]; then
 CLANG_DIR="${CC%/bin/clang}"
else
 CLANG_DIR="$TOOLCHAIN_DIR/clang"
fi
CLANG_NAME="$(grep -hoE 'clang-r[0-9]+[a-z]*' "$README_FILE" 2>/dev/null | head -n 1 || echo "")"
if [[ "$VERSION" = "5" && "$PATCHLEVEL" = "4" && -z "$CLANG_NAME" ]]; then
 mkdir -p "$CLANG_DIR"
 curl -LO https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/llvm-arm-toolchain-ship-10.0.9.tar.gz
 tar -xzf llvm-arm-toolchain-ship-10.0.9.tar.gz -C "$CLANG_DIR"
 rm -f llvm-arm-toolchain-ship-10.0.9.tar.gz
elif [ -n "$CLANG_NAME" ]; then
 get_script "get_clang.sh"
else
 echo "Error: Can not identify clang name." >&2
 exit 1
fi

# Download GCC if toolchain is required
if [ "$GCC64" = true ] || [ "$GCC32" = true ]; then
 if [ ! -d "$GCC_DIR" ]; then get_script "get_gcc.sh"; fi
fi

# ==============================================================================
# 7. BUILD OPTIONS
# ==============================================================================
BUILD_OPTIONS=(
    -C "${KERNEL_DIR}"
    O="${KERNEL_DIR}/out"
    -j"$(nproc)"
    ARCH="${ARCH}"
    CC="ccache ${CLANG_DIR}/bin/clang"
    CLANG_TRIPLE="${CLANG_TRIPLE}"
)

if [[ "$VERSION" -gt "4" ]] || [[ "$VERSION" -eq "4" && "$PATCHLEVEL" -gt "14" ]]; then
 BUILD_OPTIONS+=( LLVM=1 LLVM_IAS=1 )
elif [ "$ARCH" = "arm64" ]; then
 export CROSS_COMPILE="${CROSS_COMPILE:-${GCC_DIR}/aarch64/bin/aarch64-linux-android-}"
 BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
else
 export CROSS_COMPILE="${CROSS_COMPILE:-${GCC_DIR}/arm/bin/arm-linux-androideabi-}"
 BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
fi

if [ "$GCC32" = true ]; then
 export CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-${GCC_DIR}/arm/bin/arm-linux-androideabi-}"
 BUILD_OPTIONS+=( CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" )
fi

# ==============================================================================
# 8. BUILDING PROCESS
# ==============================================================================
export KBUILD_BUILD_USER="@Tam97123"
export PATH="${CLANG_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"
eval "$(grep '^export ' "$KERNEL_DIR/build_kernel.sh" 2>/dev/null)"

# Export ccache to speed up building
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache || echo "/usr/bin/ccache")
ccache -M 50G >/dev/null

echo "================================================="
echo "[+] Generating Defconfig..."
make "${BUILD_OPTIONS[@]}" $DEFCONFIG $CUSTOM_DEFCONFIG 2>&1 | tee build.log

echo "================================================="
echo "[+] Compiling Kernel..."
make "${BUILD_OPTIONS[@]}" 2>&1 | tee -a build.log
