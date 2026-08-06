#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
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
DEFCONFIG=
KSU=

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
 elif command -v pacman &> /dev/null; then
  echo "[+] Arch-based system detected, using pacman..."
  sudo pacman -Sy --needed --noconfirm base-devel
  sudo pacman -S --needed --noconfirm dtc lz4 xz zlib jdk-openjdk python \
   p7zip android-tools erofs-utils \
   ncurses ccache libx11 readline mesa python-markdown \
   libxml2 libxslt dos2unix kmod openssl libelf pahole \
   libarchive zstd rsync libyam
 else
  echo "[-] Error: Can not determine package manager, please install dependencies manually" >&2
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
# 3. CHECK DEFCONFIG
# ==============================================================================
validate_defconfigs() {
 local input_configs="$1"
 local valid_names=""
 local valid_paths=""

 for config in $input_configs; do
  local config_path=$(find "${DEFCONFIG_DIR[@]}" -type f -name "$config" -print -quit 2>/dev/null)
  if [ -n "$config_path" ]; then
   valid_names="$valid_names $(basename "$config_path")"
   valid_paths="$valid_paths $config_path"
  else
   echo "[-] Error: No such defconfig name ${config}" >&2
   return 1
  fi
 done
 VALID_DEFCONFIG_NAMES="${valid_names# }"
 VALID_DEFCONFIG_PATHS="${valid_paths# }"
 return 0
}

if [ -z "$DEFCONFIG" ]; then
 while true; do
  read -p "Enter defconfig (supports multiple, space-separated): " user_input
   if [ -z "$user_input" ]; then
    echo -e "\nDefconfig is necessary when building kernel"
    continue
   fi
   if validate_defconfigs "$user_input"; then
    DEFCONFIG="$VALID_DEFCONFIG_NAMES"
    break
  fi
 done
else
 if ! validate_defconfigs "$DEFCONFIG"; then exit 1; fi
 DEFCONFIG="$VALID_DEFCONFIG_NAMES"
fi
echo "[+] Using ${DEFCONFIG} as defconfig"

# ==============================================================================
# 4. DETECT ARCHITECTURE
# ==============================================================================
check_flag() {
    local flag="$1"
    for path in $VALID_DEFCONFIG_PATHS; do
     if grep -q "$flag" "$path" 2>/dev/null; then return 0; fi
    done
    return 1
}

if check_flag "CONFIG_ARM64=y"; then
 export ARCH=arm64
 export CLANG_TRIPLE="aarch64-linux-gnu-"
 GCC64=true
 if check_flag "CONFIG_COMPAT_VDSO=y"; then
  GCC32=true
  echo "[+] Detected 64-bit Kernel (aarch64). Kernel needs 64-bit & 32-bit GCC"
 else
  echo "[+] Detected 64-bit Kernel (aarch64). Kernel only needs 64-bit GCC"
 fi
else
 export ARCH=arm
 export CLANG_TRIPLE="arm-linux-gnueabi-"
 GCC32=true
 echo "[+] Detected 32-bit Kernel (arm). Kernel only needs 32-bit GCC"
fi

# ==============================================================================
# 5. DOWNLOAD TOOLCHAIN
# ==============================================================================
if [ ! -d "$CLANG_DIR" ]; then get_script "get_clang.sh"; fi

# Download GCC if toolchain is required
if [ "$GCC64" = true ] || [ "$GCC32" = true ]; then
 if [ ! -d "$GCC_DIR" ]; then get_script "get_gcc.sh"; fi
fi

# ==============================================================================
# (OPTIONAL) INTEGRATE KERNELSU
# ==============================================================================
integrate_ksu () {
 get_script "integrate_ksu.sh"
 echo "[+] Downloading defconfig to enable KernelSU"
 if ! curl -sL "$REPO_URL/defconfig/ksu_defconfig" -o "$KSU_DEFCONFIG"; then
  echo "Error: Can not download defconfig" >&2
  exit 1
 fi
}

integrate_ksu_susfs () {
 get_script "integrate_ksu_susfs.sh"
 echo "[+] Downloading defconfig to enable KernelSU with SUSFS"
  if ! curl -sL "$REPO_URL/defconfig/ksu-susfs_defconfig" -o "$KSU_DEFCONFIG"; then
   echo "[-] Error: Can not download DEFCONFIG." >&2
   exit 1
  fi
}

if [ -z "$KSU" ]; then
 while true; do
  read -t 10 -p "Integrate KSU? [y/n]: " KSU || true
  if [[ "$KSU" = "Y" || "$KSU" = "y" || "$KSU" = "N" || "$KSU" = "n" || -z "$KSU" ]]; then
   break
  else
   echo "Unknown answer: ${KSU}"
  fi
 done
fi

if [[ "$KSU" = "Y" || "$KSU" = "y" ]]; then
 KSU_DEFCONFIG="$KERNEL_DIR/arch/$ARCH/configs/custom.config"
 if [[ "$KERNEL_VERSION" = "3.18" && "$KERNEL_VERSION" = "4.4"]]; then
  echo "[+] Integrate KernelSU..."
  integrate_ksu
 elif [[ "$VERSION" -eq "4" || "$KERNEL_VERSION" = "5.4" ]]; then
  echo "[+] Integrate KernelSU with SUSFS..."
  integrate_ksu_susfs
 else
  echo "[-] This kernel script does not support kernel ${KERNEL_VERSION}!" >&2
  exit 1
 fi
 DEFCONFIG="${DEFCONFIG} custom.config"
elif [[ "$KSU" = "N" || "$KSU" = "n" || -z "$KSU" ]]; then
 echo "[-] Skipping integrate KernelSU!"
else
 echo "[-] Error: Unknown answer: ${KSU}" >&2
 exit 1
fi

# ==============================================================================
# 6. BUILD OPTIONS
# ==============================================================================
BUILD_OPTIONS=(
 -C "${KERNEL_DIR}"
 O="${KERNEL_DIR}/out"
 -j"$(nproc)"
 ARCH="${ARCH}"
 CC="ccache ${CLANG_DIR}/bin/clang"
 CLANG_TRIPLE="${CLANG_TRIPLE}"
)

if [[ "$VERSION" -gt "4" || ( "$VERSION" -eq "4" && "$PATCHLEVEL" -gt "14" ) ]]; then
 BUILD_OPTIONS+=( LLVM=1 LLVM_IAS=1 )
elif [ "$ARCH" = "arm64" ]; then
 export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
 if [ "$GCC32" = true ]; then
  export CROSS_COMPILE_ARM32="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
  export CROSS_COMPILE_COMPAT="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
  BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT}" )
 else
  BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
 fi
else
 export CROSS_COMPILE="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
 BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
fi

# ==============================================================================
# 7. BUILDING PROCESS
# ==============================================================================
export KBUILD_BUILD_USER="@Tam97123"
export PATH="${CLANG_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"

# Export ccache to speed up building
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache || echo "/usr/bin/ccache")
ccache -M 50G >/dev/null

echo "[+] Generating Defconfig..."
make "${BUILD_OPTIONS[@]}" $DEFCONFIG

echo "[+] Compiling Kernel..."
make "${BUILD_OPTIONS[@]}" 2>&1 | tee -a build.log
