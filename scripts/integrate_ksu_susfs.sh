#!/bin/bash
REJECT_DIR=$KERNEL_DIR/patch_rejects

# Abort scripts for kernel 4.4 and older
if [[ "$VERSION" -eq "4" && "$PATCH_LEVEL" -eq "4" ]]; then
 echo "SUSFS does not support kernel 4.4! Use manual hook or backport manually instead."
 exit 1
elif [ "$VERSION" -lt "4" ]; then
 echo "SUSFS does not support kernel older than version 4.x ! Please backport manually."
fi

# Integrate KernelSU (ReSukiSU)
if [ ! -d "$KERNEL_DIR/KernelSU" ]; then
 echo "Downloading KernelSU..."
 if ! curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash; then
  echo "Error: Can not download KernelSU"
  exit 1
 fi
fi

# UI only, you can remove these or comment out
sed -i 's|$(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))|%TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay/|' "$KERNEL_DIR/KernelSU/kernel/KBuild"
sed -i '/-dirty/d' "$KERNEL_DIR/KernelSU/kernel/KBuild"

# Patch SUSFS (temporary for non gki)
if [[ "$VERSION" -lt "5" || ( "$VERSION" -eq "5" && "$PATCH_LEVEL" -eq "4" ) ]]; then
 if [ ! -f "$KERNEL_DIR/susfs_inline_hook_patches.sh" ]; then
  echo "Downloading script..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh; then
   echo "Error: Can not download script."
   exit 1
  fi
  chmod +x && ./susfs_inline_hook_patches.sh
 fi

 if [ ! -f "$KERNEL_DIR/susfs_patch_to_$VERSION.$PATCH_VERSION.patch" ]; then
  echo "Downloading patch..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/Patch/susfs_patch_to_$VERSION.$PATCH_VERSION.patch; then
   echo "Error: Can not download patch"
   exit 1
  fi
  patch -p1 < "susfs_patch_to_$VERSION.$PATCH_LEVEL.patch"
 fi
else
 echo "Temporary not support GKI kernel. Aborting..."
 exit 1
fi

mapfile -t REJ_FILES < <(find . -name "*.rej")

# Check if the array has any items
if [ ${#REJ_FILES[@]} -gt 0 ]; then
 echo "Found fail patches!."
 read -t 10 -p "Continue build kernel? (y/N): " COLLECT_REJECTS
 while true; do
  if [ -z "$COLLECT_REJECTS" ]; then
   echo ""
   echo "[+] Collecting .rej and .orig files into $REJECT_DIR and continue"
   mkdir -p "$REJECT_DIR"
   find . -type f \( -name "*.rej" -o -name "*.orig" \) -exec mv {} "$REJECT_DIR/" \;
   break
  elif [[ "$COLLECT_REJECTS" =~ ^[Yy]$ ]]; then
   echo "[+] Deleting .rej and .orig files and CONTINUING..."
   find . -type f \( -name "*.rej" -o -name "*.orig" \) -delete
   break
  elif [[ "$COLLECT_REJECTS" =~ ^[Nn]$ ]]; then
   echo "[-] Collecting .rej and .orig files into $REJECT_DIR. Aborting..."
   mkdir -p "$REJECT_DIR"
   find . -type f \( -name "*.rej" -o -name "*.orig" \) -exec mv {} "$REJECT_DIR/" \;
   exit 1
  else
   echo "Unknown answer: $COLLECT_REJECTS"
  fi
 done
fi
