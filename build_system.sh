#!/bin/bash

# This script simulates an Android build system.
# It sets up the build environment, compiles the code, and creates the output directories.

# --- Clean Up ---
# Remove the output directory to ensure a clean build.
if [ -d "out" ]; then
    echo "[*] Removing previous build artifacts..."
    rm -rf "out"
fi

# --- Build Environment Setup ---

# Display a message indicating the start of the build process.
echo "[*] Initializing MiniDroid Build Environment..."

# Define the output directories, mimicking the Android Open Source Project (AOSP) structure.
OUT_DIR="out/target/product/generic"
SYSTEM_DIR="$OUT_DIR/system"
VENDOR_DIR="$OUT_DIR/vendor"

# Create the output directories.
mkdir -p "$SYSTEM_DIR"/bin
mkdir -p "$SYSTEM_DIR"/framework
mkdir -p "$SYSTEM_DIR"/app
mkdir -p "$SYSTEM_DIR"/etc/manifests
mkdir -p "$VENDOR_DIR"/lib64

echo "[*] Build environment initialized in: $OUT_DIR"

# --- Build Steps ---

# 1. Build Java
# This block compiles the Java Launcher application using Maven, copies the resulting
# JAR file to the simulated system image, and also copies the `pom.xml` manifest file.
# The `pom.xml` is essential for SBOM tools to identify the project and its dependencies.
echo "[*] Building Java Frameworks..."
if command -v mvn &> /dev/null; then
    echo "    - Building Launcher app with Maven..."
    (cd packages/apps/Launcher && mvn package)
    echo "    - Copying JAR to system/app..."
    cp packages/apps/Launcher/target/*.jar "$SYSTEM_DIR/app/Launcher.jar"
    echo "    - Copying manifest to system/etc/manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/Launcher"
    cp packages/apps/Launcher/pom.xml "$SYSTEM_DIR/etc/manifests/Launcher/pom.xml"
    echo "    - Built and installed Launcher.jar to system/app"
else
    echo "    - Maven not found. Skipping Java build."
    touch "$SYSTEM_DIR/app/Launcher.jar"
fi

# 2. Build C/C++
# This block compiles the native C service using GCC. It uses Conan to manage
# dependencies and copies the `conanfile.py` and `conan.lock` as its SBOM manifest.
echo "[*] Building Native Layers (C/C++)..."
if command -v gcc &> /dev/null; then
    if command -v conan &> /dev/null; then
        echo "    - Installing C/C++ dependencies with Conan..."
        conan profile detect --force
        (cd system/core && conan install .)
    else
        echo "    - Conan not found. Skipping C/C++ dependency installation."
    fi
    echo "    - Compiling system/core/native_service.c..."
    gcc system/core/native_service.c -o "$SYSTEM_DIR/bin/native_service"
    echo "    - Copying manifest to system/etc/manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/native_service"
    cp system/core/conanfile.py "$SYSTEM_DIR/etc/manifests/native_service/conanfile.py"
    if [ -f "system/core/conan.lock" ]; then
        cp system/core/conan.lock "$SYSTEM_DIR/etc/manifests/native_service/conan.lock"
    fi
    echo "    - Built system/bin/native_service"
else
    echo "    - GCC not found. Creating dummy binary."
    touch "$SYSTEM_DIR/bin/native_service"
fi

# 3. Build Python
# This block creates a Python virtual environment if it doesn't exist, installs
# dependencies, and copies the tool script and manifest.
echo "[*] Installing Python Tools..."
if [ ! -f "./.venv/bin/activate" ]; then
    echo "    - Python virtual environment not found. Creating..."
    python3 -m venv ./.venv
fi
# Activate the virtual environment.
echo "    - Activating Python virtual environment..."
source "./.venv/bin/activate"
echo "    - Installing requirements from system/tools/requirements.txt..."
pip install -r system/tools/requirements.txt
echo "    - Copying sys_tool.py to system/bin..."
cp system/tools/sys_tool.py "$SYSTEM_DIR/bin/sys_tool.py"
echo "    - Copying manifest to system/etc/manifests..."
mkdir -p "$SYSTEM_DIR/etc/manifests/sys_tool"
cp system/tools/requirements.txt "$SYSTEM_DIR/etc/manifests/sys_tool/requirements.txt"
echo "    - Installed system tools"

# 4. Build Go
# This block compiles the Go microservice into a static binary. It then copies the
# `go.mod` and `go.sum` files into the output directory. These files define the
# module's dependencies, allowing SBOM tools to catalog them accurately.
echo "[*] Building Go Microservices..."
if command -v go &> /dev/null; then
    echo "    - Building netdaemon..."
    (cd vendor/components/netdaemon && go mod tidy && go build -o "$OLDPWD/$SYSTEM_DIR/bin/netdaemon" .)
    echo "    - Copying manifests to system/etc/manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/netdaemon"
    cp vendor/components/netdaemon/go.mod "$SYSTEM_DIR/etc/manifests/netdaemon/"
    cp vendor/components/netdaemon/go.sum "$SYSTEM_DIR/etc/manifests/netdaemon/"
    echo "    - Built and installed netdaemon to system/bin"
else
    echo "    - Go not found. Skipping Go microservice build."
    touch "$SYSTEM_DIR/bin/netdaemon"
fi

# 5. Build Rust
# This block compiles the Rust component using Cargo in release mode. The resulting
# binary is copied to the vendor directory. The `Cargo.toml` and `Cargo.lock` files
# are also copied to provide a detailed manifest of all dependencies (crates).
echo "[*] Building Rust Components..."
if command -v cargo &> /dev/null; then
    echo "    - Building secure_enclave with Cargo..."
    (cd vendor/components/secure_enclave && cargo build --release)
    echo "    - Copying binary to vendor/lib64..."
    cp vendor/components/secure_enclave/target/release/secure-enclave "$VENDOR_DIR/lib64/secure_enclave"
    echo "    - Copying manifests to system/etc/manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/secure_enclave"
    cp vendor/components/secure_enclave/Cargo.toml "$SYSTEM_DIR/etc/manifests/secure_enclave/"
    cp vendor/components/secure_enclave/Cargo.lock "$SYSTEM_DIR/etc/manifests/secure_enclave/"
    echo "    - Built and installed secure_enclave to vendor/lib64"
else
    echo "    - Cargo not found. Skipping Rust component build."
    touch "$VENDOR_DIR/lib64/secure_enclave"
fi

# --- Build Completion ---

# Display a message indicating the completion of the build process.
echo "[*] Build Complete."
echo "    Artifacts located in: $OUT_DIR"
