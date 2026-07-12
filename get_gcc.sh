#!/bin/bash

if ! git clone https://github.com/JackA1ltman/Google-GCC-Android-4.9 -b aarch64 "$GCC_DIR/aarch64"; then
 echo "Error: Can not download gcc64! Exiting..."
 exit 1
elif ! git clone https://github.com/JackA1ltman/Google-GCC-Android-4.9 -b arm32 "$GCC_DIR/arm32"; then
 echo "Error: Can not download gcc32! Exiting..."
 exit 1
fi
