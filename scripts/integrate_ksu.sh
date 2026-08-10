#!/bin/bash
set -euo pipefail

# ==============================================================================
# 1. INTEGRATE KERNELSU (ReSukiSU)
# ==============================================================================
if [ ! -d "$KERNEL_DIR/KernelSU" ]; then
 echo "[+] Downloading KernelSU..."
 if ! curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash >/dev/null 2>&1; then
  echo "[-] Error: Cannot download KernelSU" >&2
  exit 1
 fi
elif [ -f "$KERNEL_DIR/KernelSU/kernel/Kbuild" ]; then
 sed -i 's|$(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))|%TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay|' "$KERNEL_DIR/KernelSU/kernel/Kbuild"
 sed -i '/-dirty/d' "$KERNEL_DIR/KernelSU/kernel/Kbuild"
fi

# ==============================================================================
# 2. PATCH KERNELSU
# ==============================================================================
if [ ! -f "$KERNEL_DIR/.ksu_patch" ]; then
 echo "[+] Downloading SUSFS inline hook script..."
 if ! curl -sLO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh; then
  echo "[-] Error: Cannot download script." >&2
  exit 1
 fi
 bash syscall_hook_patches.sh >/dev/null 2>&1
 rm -f syscall_hook_patches.sh
fi
