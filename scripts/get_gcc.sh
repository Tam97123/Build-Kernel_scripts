#!/bin/bash

if [ "$GCC64" = true ]; then
 if [ ! -d "$GCC_DIR/aarch64" ]; then
  echo "Downloading GCC aarch64..."
   if ! git clone https://github.com/JackAlltman/Google-GCC-Android-4.9 -b aarch64 "$GCC_DIR/aarch64"; then
    echo "Error: Can not download gcc64!"
    exit 1
   fi
  else
   echo "[*] GCC aarch64 already exists. Skipping download."
  fi
fi

if [ "$GCC32" = true ]; then
 if [ ! -d "$GCC_DIR/arm" ]; then
  echo "[+] Downloading GCC arm32..."
  if ! git clone https://github.com/JackAlltman/Google-GCC-Android-4.9 -b arm32 "$GCC_DIR/arm"; then
   echo "Error: Can not download gcc32!"
   exit 1
  fi
 else
  echo "[*] GCC arm32 already exists. Skipping download."
 fi
fi
