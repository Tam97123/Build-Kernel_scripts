#!/bin/bash
REJECT_DIR=$KERNEL_DIR/patch_rejects

# Integrate KernelSU (ReSukiSU)
if [ ! -d "$KERNEL_DIR/KernelSU" ]; then
 echo "Downloading KernelSU..."
 if ! curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash; then
  echo "Error: Can not download KernelSU"
  exit 1
 fi
fi

# For UI, you can remove these or comment out
sed -i 's|$(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))|%TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay/|' "$KERNEL_DIR/KernelSU/kernel/Kbuild"
sed -i '/-dirty/d' "$KERNEL_DIR/KernelSU/kernel/Kbuild"

# Patch SUSFS (temporary for non gki)
if [[ "$VERSION" -lt "5" || ( "$VERSION" -eq "5" && "$PATCH_LEVEL" -eq "4" ) ]]; then
 if [ ! -f "$KERNEL_DIR/susfs_inline_hook_patches.sh" ]; then
  echo "Downloading script..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh; then
   echo "Error: Can not download script."
   exit 1
  fi
  chmod +x susfs_inline_hook_patches.sh && ./susfs_inline_hook_patches.sh
 fi

 if [ ! -f "$KERNEL_DIR/susfs_patch_to_$VERSION.$PATCH_LEVEL.patch" ]; then
  echo "Downloading patch..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/Patch/susfs_patch_to_$VERSION.$PATCH_LEVEL.patch; then
   echo "Error: Can not download patch"
   exit 1
  fi
  patch -p1 < "susfs_patch_to_$VERSION.$PATCH_LEVEL.patch" || true
 fi
else
 echo "Temporary not support GKI kernel. Aborting..."
 exit 1
fi

move_rejects() {
 find . -type f -name "*.rej" -print0 | while IFS= read -r -d $'\0' rej_file; do
  mkdir -p "$REJECT_DIR"
  local rej_dir=$(dirname "$rej_file")
  mkdir -p "$REJECT_DIR/$rej_dir" 
  mv "$rej_file" "$REJECT_DIR/$rej_dir/"
 
  local orig_file="${rej_file%.rej}.orig"
  if [ -f "$orig_file" ]; then
    mv "$orig_file" "$REJECT_DIR/$rel_dir/"
  fi
 done
}

delete_rejects() { find . -type f -name "*.rej" -print0 | while IFS= read -r -d $'\0' rej_file; do rm -f "$rej_file"; done }

mapfile -t REJ_FILES < <(find . -name "*.rej")

if [ ${#REJ_FILES[@]} -gt 0 ]; then
 echo "Found fail patches!"
 while true; do
  if read -t 10 -p "Continue build kernel? (y/N): " COLLECT_REJECTS; then
   if [ -z "$COLLECT_REJECTS" ]; then
    echo -e "\n[+] Collecting rejects and it's original files into $REJECT_DIR and continue."
    move_rejects
    break
   elif [[ "$COLLECT_REJECTS" =~ ^[Yy]$ ]]; then
    echo "[+] Deleting rejects files and continue."
    delete_rejects
    break
   elif [[ "$COLLECT_REJECTS" =~ ^[Nn]$ ]]; then
    echo "[-] Collecting rejects and it's original files into $REJECT_DIR. Aborting..."
    move_rejects
    exit 1
   else
    echo "Unknown answer: $COLLECT_REJECTS"
   fi
  else
   echo -e "\n[+] Collecting rejects and it's original files into $REJECT_DIR and continue."
   move_rejects
   break
  fi
 done
fi
