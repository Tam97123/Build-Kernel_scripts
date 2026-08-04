#!/bin/bash
set -euo pipefail

REJECT_DIR="$KERNEL_DIR/patch_rejects"

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
# 2. PATCH KERNELSU & SUSFS
# ==============================================================================
if [ ! -f "$KERNEL_DIR/.ksu_patch" ]; then
 echo "[+] Downloading SUSFS inline hook script..."
 if ! curl -sLO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh; then
  echo "[-] Error: Cannot download script." >&2
  exit 1
 fi
 chmod +x susfs_inline_hook_patches.sh
 bash susfs_inline_hook_patches.sh >/dev/null 2>&1
 rm -f susfs_inline_hook_patches.sh
 if [ ! -f "$KERNEL_DIR/susfs_patch_to_${KERNEL_VERSION}" ]; then
  PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/Patch/susfs_patch_to_${KERNEL_VERSION}.patch"
  echo "[+] Downloading SUSFS patch for kernel ${KERNEL_VERSION}..."
  if ! curl -sLO "$PATCH_URL"; then
   echo "[-] Error: Cannot download patch file" >&2
   exit 1
  fi
  echo "[+] Applying SUSFS patch..."
  patch -p1 < "susfs_patch_to_${KERNEL_VERSION}.patch" || true
  rm -f susfs_patch_to_${KERNEL_VERSION}.patch
 fi
fi

# ==============================================================================
# 3. PATCH CONFLICT HANDLER FUNCTIONS
# ==============================================================================
mapfile -d $'\0' REJ_FILES < <(find . -type f -name "*.rej" -print0)
REJ_COUNT=${#REJ_FILES[@]}

if [ "$REJ_COUNT" -eq 1 ] && [ -z "${REJ_FILES[0]}" ]; then
 REJ_COUNT=0
fi

move_rejects() {
    mkdir -p "$REJECT_DIR"
    for rej_file in "${REJ_FILES[@]}"; do
     [ -z "$rej_file" ] && continue
     local rej_dir
     rej_dir=$(dirname "$rej_file")
     mkdir -p "$REJECT_DIR/$rej_dir" 
     mv "$rej_file" "$REJECT_DIR/$rej_dir/"
    done
}

delete_rejects() {
    for rej_file in "${REJ_FILES[@]}"; do
     [ -z "$rej_file" ] && continue
     rm -f "$rej_file"
    done
}

if [ "$REJ_COUNT" -gt 0 ]; then
 echo "[-] Warning: Found $REJ_COUNT failed patch rejections (.rej)!"
 while true; do
  read -t 10 -p "Continue them?: " COLLECT_REJECTS || true
  if [ -z "$COLLECT_REJECTS" ]; then
   echo -e "\n[+] No respone. Collecting rejects into $REJECT_DIR and continue"
   move_rejects
   break
  elif [[ "$COLLECT_REJECTS" == "Y" || "$COLLECT_REJECTS" == "y" ]]; then
   echo "[+] Deleting reject files and continue"
   delete_rejects
   break
  elif [[ "$COLLECT_REJECTS" == "N" || "$COLLECT_REJECTS" == "n" ]]; then
   echo "[-] Collecting rejects into $REJECT_DIR and abort" >&2
   move_rejects
   exit 1
  else
   echo "[?] Unknown answer: '$COLLECT_REJECTS'"
  fi
 done
fi
