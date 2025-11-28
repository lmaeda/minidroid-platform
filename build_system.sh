#!/bin/bash

# This script simulates an Android build system.
# It sets up the build environment, compiles the code, and creates the output directories.

# --- Build Environment Setup ---

# Display a message indicating the start of the build process.
echo "[*] Initializing MiniDroid Build Environment..."

# Define the output directories, mimicking the Android Open Source Project (AOSP) structure.
OUT_DIR="out/target/product/generic"
SYSTEM_DIR="$OUT_DIR/system"
VENDOR_DIR="$OUT_DIR/vendor"

# Create the output directories.
mkdir -p $SYSTEM_DIR/bin
mkdir -p $SYSTEM_DIR/framework
mkdir -p $SYSTEM_DIR/app
mkdir -p $SYSTEM_DIR/etc
mkdir -p $VENDOR_DIR/lib64

# --- Build Steps ---

# Build the native C/C++ layers.
echo "[*] Building Native Layers (C/C++)..."
# Compile the C binary using gcc.
if command -v gcc &> /dev/null; then
    gcc system/core/native_service.c -o $SYSTEM_DIR/bin/native_service
    echo "    - Built system/bin/native_service"
else
    # If gcc is not found, create a dummy binary.
    echo "    - GCC not found. Creating dummy binary."
    touch $SYSTEM_DIR/bin/native_service
fi

# Build the Java frameworks.
echo "[*] Building Java Frameworks..."
if command -v mvn &> /dev/null; then
    (cd packages/apps/Launcher && mvn package)
    cp packages/apps/Launcher/target/*.jar $SYSTEM_DIR/app/Launcher.jar
    echo "    - Built and installed Launcher.jar to system/app"
else
    echo "    - Maven not found. Skipping Java build."
    touch $SYSTEM_DIR/app/Launcher.jar
fi

# Install the Python tools.
echo "[*] Installing Python Tools..."
if [ -f "$HOME/workspace/venvs/pyenv3.13_minidroid/bin/activate" ]; then
    # Activate the virtual environment.
    source "$HOME/workspace/venvs/pyenv3.13_minidroid/bin/activate"
    pip install -r system/tools/requirements.txt
    cp system/tools/sys_tool.py $SYSTEM_DIR/bin/sys_tool.py
    echo "    - Installed system tools"
else
    echo "    - Python virtual environment not found. Skipping Python tools installation."
fi


# Build the Go microservices.
echo "[*] Building Go Microservices..."
if command -v go &> /dev/null; then
    go build -o $SYSTEM_DIR/bin/netdaemon vendor/components/netdaemon/main.go
    echo "    - Built and installed netdaemon to system/bin"
else
    echo "    - Go not found. Skipping Go microservice build."
    touch $SYSTEM_DIR/bin/netdaemon
fi

# Build the Rust components.
echo "[*] Building Rust Components..."
if command -v cargo &> /dev/null; then
    (cd vendor/components/secure_enclave && cargo build --release)
    cp vendor/components/secure_enclave/target/release/secure_enclave $VENDOR_DIR/lib64/secure_enclave
    echo "    - Built and installed secure_enclave to vendor/lib64"
else
    echo "    - Cargo not found. Skipping Rust component build."
    touch $VENDOR_DIR/lib64/secure_enclave
fi

# --- Build Completion ---

# Display a message indicating the completion of the build process.
echo "[*] Build Complete."
echo "    Artifacts located in: $OUT_DIR"
