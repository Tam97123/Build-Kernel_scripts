#!/bin/bash

echo "[+] Setting up Clang toolchain..."
CLANG_NAME="${CLANG_NAME:-$(grep -hoE 'clang-r[0-9]+[a-z]*' "$KERNEL_DIR"/build.config.* 2>/dev/null | head -n 1)}"

if [ -z "$CLANG_NAME" ]; then
 echo "[-] Error: Cannot identify clang name." >&2
 exit 1
fi

echo "[+] Target Clang version: $CLANG_NAME"
echo "[+] Fetching AOSP history (blobless clone)..."

if ! git clone --filter=blob:none --no-checkout https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp_clang; then
 echo "[-] Error: Cannot fetch AOSP history from Google." >&2
 exit 1
fi

cd aosp_clang

echo "[+] Searching for $CLANG_NAME in git history..."
CLANG_TARGET=$(git log -n 1 --all --diff-filter=AM --format="%H" -- "$CLANG_NAME")

if [ -z "$CLANG_TARGET" ]; then
 cd .. && rm -rf aosp_clang
 echo "[-] Error: '$CLANG_NAME' not found in AOSP history." >&2
 exit 1
fi

echo "[+] Checking out toolchain (Sparse Checkout)..."
git sparse-checkout init --cone >/dev/null 2>&1
git sparse-checkout set "$CLANG_NAME" >/dev/null 2>&1
git checkout "$CLANG_TARGET" >/dev/null 2>&1

mkdir -p "$TOOLCHAIN_DIR"
mv "$CLANG_NAME" "$CLANG_DIR"
cd .. && rm -rf aosp_clang

echo "[+] Clang toolchain successfully set up at $CLANG_DIR"
