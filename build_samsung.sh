#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
README_FILE=$(find "$(dirname "$KERNEL_DIR")" -name "README_Kernel.txt" -print -quit)
if [ -z "$README_FILE" ]; then
    echo "Error: It is necessary to follow README from SAMSUNG (README_Kernel.txt not found)."
    exit 1
fi

KERNEL_VERSION=$( (head -n 3 Makefile | awk '/^VERSION|PATCHLEVEL/ {print $3}' | paste -sd '.') || true )
TOOLCHAIN=$KERNEL_DIR/toolchain
GCC_DIR=$TOOLCHAIN_DIR/gcc/linux-x86
DEFCONFIG_DIR="$KERNEL_DIR/arch/arm64/configs"
REPO_URL="https://raw.githubusercontent.com/Tam97123/Build-Kernel_scripts/refs/heads/main"
# Hardcode these variable if you don't want prompt
CUSTOM_DEFCONFIG=

DEFCONFIG=$(grep -oE '[a-zA-Z0-9_-]+_defconfig' "$README_FILE" | head -n 1)
if [ -z "$DEFCONFIG" ]; then
    echo "Error: Could not find defconfig to use in README."
    exit 1
fi

# Function to detect OS and install dependencies
install_dependencies () {
    echo "Detecting OS and installing dependencies..."
    if command -v apt &> /dev/null; then
     echo "Ubuntu/Debian-based system detected, using apt..."
     sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
      default-jdk gnupg flex bison gperf build-essential zip curl ccache libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
      make sudo bc grep tofrodos python3-markdown libxml2-utils xsltproc libtinfo6 \
      repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd libyaml-dev --fix-missing && \
      wget http://mirrors.kernel.org/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.2_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.2_amd64.deb && rm -f libtinfo5_6.3-2ubuntu0.2_amd64.deb
    elif command -v dnf &> /dev/null; then
     echo "Fedora/RHEL-based system detected, using dnf..."
     sudo dnf group install "c-development" "development-tools" && \
     sudo dnf install -y dtc lz4 xz zlib-devel java-latest-openjdk-devel python3 \
      p7zip p7zip-plugins android-tools erofs-utils \
      ncurses-devel ccache libX11-devel readline-devel mesa-libGL-devel python3-markdown \
      libxml2 libxslt dos2unix kmod openssl elfutils-libelf-devel dwarves \
      openssl-devel libarchive zstd rsync libyaml-devel openssl-devel-engine --skip-unavailable
    else
     echo "Error: Can not determine package manager, please install dependencies manually."
     exit 1
    fi
    touch .requirements
}

# Install the requirements for building the kernel when running the script for the first time
if [ ! -f ".requirements" ]; then
 install_dependencies
fi

extract_toolchain_path() {
  local toolchain="$1"

  if grep -q "$toolchain" "$README_FILE"; then
   local toolchain_line
   toolchain_line=$(grep -m 1 "${toolchain}=/usr/local" "$README_FILE" || true)    
   if [ -z "$toolchain_line" ]; then
    echo "Error: Can not get path from README for $toolchain"
    exit 1
   fi

   local toolchain_path
   toolchain_path=$(echo "$toolchain_line" | sed -n "s/.*${toolchain}=\/usr\/local\([^ ]*\).*/\1/p")

   declare -g "$toolchain"="${KERNEL_DIR}${toolchain_path}"
   export "$toolchain"
  fi
}

get_gcc() {
    echo "Downloading scripts..."
    if ! curl -LO "$REPO_URL/scripts/get_gcc.sh"; then
     echo "Error: Can not download the file!"
     exit 1
    fi
    source ./get_gcc.sh
    rm -f get_gcc.sh
}

get_clang () {
    echo "Downloading scripts..."
    if ! curl -LO "$REPO_URL/scripts/get_clang.sh"; then
     echo "Error: Can not download the file!"
     exit 1
    fi
    source ./get_clang.sh
    rm -f get_clang.sh
}

if [ -z "$KERNEL_VERSION" ]; then
 echo "Error: Can not detect kernel version!"
 exit 1
else
 VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
 PATCH_LEVEL=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')
 if [[ ( "$VERSION" -eq "5" && "$PATCH_LEVEL" -gt "4" ) || "$VERSION" -gt "5" ]]; then
  echo "Not support GKI kernel ${VERSION}.${PATCH_LEVEL}!"
  exit 1
 else
  echo "Detected kernel ${VERSION}.${PATCH_LEVEL}!"
 fi
fi

extract_toolchain_path "CC"
if [ -n "$CC" ]; then
 CLANG_DIR="${CC%/bin/clang}"
else
 echo "Error: Invalid clang path"
 exit 1
fi
extract_toolchain_path "CROSS_COMPILE"
extract_toolchain_path "CROSS_COMPILE_ARM32"
extract_toolchain_path "CLANG_TRIPLE"
if [ -n "$CLANG_TRIPLE" ]; then
 export CLANG_TRIPLE=aarch64-linux-gnu-
fi

if [ ! -d "$CLANG_DIR" ]; then get_clang; fi

if [[ "$VERSION" -eq "4" && "$PATCH_LEVEL" -le "14" ]]; then
 build_gcc
 if [ ! -d "$GCC_DIR" ]; then get_gcc; fi
else
 build_without_gcc
fi

if [ -z "$CUSTOM_DEFCONFIG" ]; then
 while true; do
  if read -t 10 -p "Enter custom defconfig (support multiple): " CUSTOM_DEFCONFIG; then
   if [ -z "$CUSTOM_DEFCONFIG" ]; then
    echo -e "\nYou do not use custom defconfig"
    break
   else
    DEFCONFIGS=
    for muti_defconfigs in $CUSTOM_DEFCONFIG; do
     DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$muti_defconfigs" -print -quit)
     if [ -n "$DEFCONFIG_PATH" ]; then
      DEFCONFIGS="$DEFCONFIGS ${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
     else
      echo "Error: No such defconfig name '$muti_defconfigs'"
      continue 2
     fi
    done
    CUSTOM_DEFCONFIG="${DEFCONFIGS# }"
    echo "Use '$CUSTOM_DEFCONFIG' as custom defconfig"
    break
   fi
  else
   echo -e "\nYou do not use custom defconfig"
   break
  fi
 done
else
 DEFCONFIGS=
 for muti_defconfigs in $DEFCONFIG; do
  DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$muti_defconfigs" -print -quit)
  if [ -n "$DEFCONFIG_PATH" ]; then
   DEFCONFIGS="$DEFCONFIGS ${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
  else
   echo "Error: No such defconfig name '$muti_defconfigs'"
   exit 1
  fi
 done
 CUSTOM_DEFCONFIG="${DEFCONFIGS# }"
 echo "Use '$CUSTOM_DEFCONFIG' as custom defconfig"
fi

export ARCH=arm64
export KBUILD_BUILD_USER="@Tam97123"
export PATH="${CLANG_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"

# Use ccache to speed up build
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

build_kernel () {
    # Make with configuration.
    if [ -z "$CUSTOM_DEFCONFIG" ]; then
     make "${BUILD_OPTIONS[@]}" $DEFCONFIG 2>&1 | tee build.log
    else
     make "${BUILD_OPTIONS[@]}" $DEFCONFIG $CUSTOM_DEFCONFIG 2>&1 | tee build.log
    fi
    # Build the kernel
    make "${BUILD_OPTIONS[@]}"
}

build_kernel
