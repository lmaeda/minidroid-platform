# This script simulates an Android build system in PowerShell.
# It sets up the build environment, compiles the code, and creates the output directories.

# --- Build Environment Setup ---

# Display a message indicating the start of the build process.
Write-Host "[*] Initializing MiniDroid Build Environment..."

# Define the output directories, mimicking the Android Open Source Project (AOSP) structure.
$OUT_DIR = "out/target/product/generic"
$SYSTEM_DIR = "$OUT_DIR/system"
$VENDOR_DIR = "$OUT_DIR/vendor"

# Create the output directories.
New-Item -ItemType Directory -Force -Path "$SYSTEM_DIR/bin" | Out-Null
New-Item -ItemType Directory -Force -Path "$SYSTEM_DIR/framework" | Out-Null
New-Item -ItemType Directory -Force -Path "$SYSTEM_DIR/app" | Out-Null
New-Item -ItemType Directory -Force -Path "$SYSTEM_DIR/etc" | Out-Null
New-Item -ItemType Directory -Force -Path "$VENDOR_DIR/lib64" | Out-Null

# --- Build Steps ---

# Build the native C/C++ layers.
Write-Host "[*] Building Native Layers (C/C++)..."
# Compile the C binary using gcc.
if (Get-Command gcc -ErrorAction SilentlyContinue) {
    gcc system/core/native_service.c -o $SYSTEM_DIR/bin/native_service
    Write-Host "    - Built system/bin/native_service"
} else {
    # If gcc is not found, create a dummy binary.
    Write-Host "    - GCC not found. Creating dummy binary."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/bin/native_service" | Out-Null
}

# Build the Java frameworks.
Write-Host "[*] Building Java Frameworks..."
if (Get-Command mvn -ErrorAction SilentlyContinue) {
    Push-Location -Path "packages/apps/Launcher"; mvn package; Pop-Location
    Copy-Item -Path "packages/apps/Launcher/target/*.jar" -Destination "$SYSTEM_DIR/app/Launcher.jar"
    Write-Host "    - Built and installed Launcher.jar to system/app"
} else {
    Write-Host "    - Maven not found. Skipping Java build."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/app/Launcher.jar" | Out-Null
}

# Install the Python tools.
Write-Host "[*] Installing Python Tools..."
$VenvPath = "$HOME/workspace/venvs/pyenv3.13_minidroid/Scripts/activate.ps1"
if (Test-Path $VenvPath) {
    # Activate the virtual environment.
    . $VenvPath
    pip install -r system/tools/requirements.txt
    Copy-Item -Path "system/tools/sys_tool.py" -Destination "$SYSTEM_DIR/bin/sys_tool.py"
    Write-Host "    - Installed system tools"
} else {
    Write-Host "    - Python virtual environment not found. Skipping Python tools installation."
}

# Build the Go microservices.
Write-Host "[*] Building Go Microservices..."
if (Get-Command go -ErrorAction SilentlyContinue) {
    go build -o "$SYSTEM_DIR/bin/netdaemon" "vendor/components/netdaemon/main.go"
    Write-Host "    - Built and installed netdaemon to system/bin"
} else {
    Write-Host "    - Go not found. Skipping Go microservice build."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/bin/netdaemon" | Out-Null
}

# Build the Rust components.
Write-Host "[*] Building Rust Components..."
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Push-Location -Path "vendor/components/secure_enclave"; cargo build --release; Pop-Location
    Copy-Item -Path "vendor/components/secure_enclave/target/release/secure_enclave" -Destination "$VENDOR_DIR/lib64/secure_enclave"
    Write-Host "    - Built and installed secure_enclave to vendor/lib64"
} else {
    Write-Host "    - Cargo not found. Skipping Rust component build."
    New-Item -ItemType File -Force -Path "$VENDOR_DIR/lib64/secure_enclave" | Out-Null
}

# --- Build Completion ---

# Display a message indicating the completion of the build process.
Write-Host "[*] Build Complete."
Write-Host "    Artifacts located in: $OUT_DIR"
