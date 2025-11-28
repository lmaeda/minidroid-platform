# This script simulates an Android build system in PowerShell.
# It sets up the build environment, compiles the code, and creates the output directories.

# --- Clean Up ---
# Remove the output directory to ensure a clean build.
if (Test-Path "out") {
    Write-Host "[*] Removing previous build artifacts..."
    Remove-Item -Recurse -Force "out"
}

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
New-Item -ItemType Directory -Force -Path "$SYSTEM_DIR/etc/manifests" | Out-Null
New-Item -ItemType Directory -Force -Path "$VENDOR_DIR/lib64" | Out-Null

Write-Host "[*] Build environment initialized in: $OUT_DIR"

# --- Build Steps ---

# 1. Build Java
# This block compiles the Java Launcher application using Maven, copies the resulting
# JAR file to the simulated system image, and also copies the `pom.xml` manifest file.
# The `pom.xml` is essential for SBOM tools to identify the project and its dependencies.
Write-Host "[*] Building Java Frameworks..."
if (Get-Command mvn -ErrorAction SilentlyContinue) {
    Write-Host "    - Building Launcher app with Maven..."
    Push-Location -Path "packages/apps/Launcher"; mvn package; Pop-Location
    Write-Host "    - Copying JAR to system/app..."
    Copy-Item -Path "packages/apps/Launcher/target/*.jar" -Destination "$SYSTEM_DIR/app/Launcher.jar"
    Write-Host "    - Copying manifest to system/etc/manifests..."
    $ManifestPath = Join-Path -Path "$SYSTEM_DIR" -ChildPath "etc/manifests/Launcher"
    New-Item -ItemType Directory -Force -Path $ManifestPath | Out-Null
    Copy-Item -Path "packages/apps/Launcher/pom.xml" -Destination "$ManifestPath/pom.xml"
    Write-Host "    - Built and installed Launcher.jar to system/app"
} else {
    Write-Host "    - Maven not found. Skipping Java build."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/app/Launcher.jar" | Out-Null
}

# 2. Build C/C++
# This block compiles the native C service using GCC. It uses Conan to manage
# dependencies and copies the `conanfile.py` and `conan.lock` as its SBOM manifest.
Write-Host "[*] Building Native Layers (C/C++)..."
# Compile the C binary using gcc.
if (Get-Command gcc -ErrorAction SilentlyContinue) {
    if (Get-Command conan -ErrorAction SilentlyContinue) {
        Write-Host "    - Installing C/C++ dependencies with Conan..."
        conan profile detect --force
        Push-Location -Path "system/core"; conan install .; Pop-Location
    } else {
        Write-Host "    - Conan not found. Skipping C/C++ dependency installation."
    }
    Write-Host "    - Compiling system/core/native_service.c..."
    gcc system/core/native_service.c -o "$SYSTEM_DIR/bin/native_service"
    Write-Host "    - Copying manifest to system/etc/manifests..."
    $ManifestPath = Join-Path -Path "$SYSTEM_DIR" -ChildPath "etc/manifests/native_service"
    New-Item -ItemType Directory -Force -Path $ManifestPath | Out-Null
    Copy-Item -Path "system/core/conanfile.py" -Destination "$ManifestPath/conanfile.py"
    if (Test-Path "system/core/conan.lock") {
        Copy-Item -Path "system/core/conan.lock" -Destination "$ManifestPath/conan.lock"
    }
    Write-Host "    - Built system/bin/native_service"
} else {
    # If gcc is not found, create a dummy binary.
    Write-Host "    - GCC not found. Creating dummy binary."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/bin/native_service" | Out-Null
}

# 3. Build Python
# This block creates a Python virtual environment if it doesn't exist, installs
# dependencies, and copies the tool script and manifest.
Write-Host "[*] Installing Python Tools..."
$VenvPath = "./.venv/Scripts/activate.ps1"
if (-not (Test-Path $VenvPath)) {
    Write-Host "    - Python virtual environment not found. Creating..."
    python3 -m venv ./.venv
}
# Activate the virtual environment.
Write-Host "    - Activating Python virtual environment..."
. $VenvPath
Write-Host "    - Installing requirements from system/tools/requirements.txt..."
pip install -r system/tools/requirements.txt
Write-Host "    - Copying sys_tool.py to system/bin..."
Copy-Item -Path "system/tools/sys_tool.py" -Destination "$SYSTEM_DIR/bin/sys_tool.py"
Write-Host "    - Copying manifest to system/etc/manifests..."
$ManifestPath = Join-Path -Path "$SYSTEM_DIR" -ChildPath "etc/manifests/sys_tool"
New-Item -ItemType Directory -Force -Path $ManifestPath | Out-Null
Copy-Item -Path "system/tools/requirements.txt" -Destination "$ManifestPath/requirements.txt"
Write-Host "    - Installed system tools"

# 4. Build Go
# This block compiles the Go microservice into a static binary. It then copies the
# `go.mod` and `go.sum` files into the output directory. These files define the
# module's dependencies, allowing SBOM tools to catalog them accurately.
Write-Host "[*] Building Go Microservices..."
if (Get-Command go -ErrorAction SilentlyContinue) {
    Write-Host "    - Building netdaemon..."
    $currentDir = Get-Location
    Push-Location -Path "vendor/components/netdaemon"
    go mod tidy
    go build -o "$currentDir/$SYSTEM_DIR/bin/netdaemon" .
    Pop-Location
    Write-Host "    - Copying manifests to system/etc/manifests..."
    $ManifestPath = Join-Path -Path "$SYSTEM_DIR" -ChildPath "etc/manifests/netdaemon"
    New-Item -ItemType Directory -Force -Path $ManifestPath | Out-Null
    Copy-Item -Path "vendor/components/netdaemon/go.mod" -Destination $ManifestPath
    Copy-Item -Path "vendor/components/netdaemon/go.sum" -Destination $ManifestPath
    Write-Host "    - Built and installed netdaemon to system/bin"
} else {
    Write-Host "    - Go not found. Skipping Go microservice build."
    New-Item -ItemType File -Force -Path "$SYSTEM_DIR/bin/netdaemon" | Out-Null
}

# 5. Build Rust
# This block compiles the Rust component using Cargo in release mode. The resulting
# binary is copied to the vendor directory. The `Cargo.toml` and `Cargo.lock` files
# are also copied to provide a detailed manifest of all dependencies (crates).
Write-Host "[*] Building Rust Components..."
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Host "    - Building secure_enclave with Cargo..."
    Push-Location -Path "vendor/components/secure_enclave"; cargo build --release; Pop-Location
    Write-Host "    - Copying binary to vendor/lib64..."
    Copy-Item -Path "vendor/components/secure_enclave/target/release/secure-enclave" -Destination "$VENDOR_DIR/lib64/secure_enclave"
    Write-Host "    - Copying manifests to system/etc/manifests..."
    $ManifestPath = Join-Path -Path "$SYSTEM_DIR" -ChildPath "etc/manifests/secure_enclave"
    New-Item -ItemType Directory -Force -Path $ManifestPath | Out-Null
    Copy-Item -Path "vendor/components/secure_enclave/Cargo.toml" -Destination $ManifestPath
    Copy-Item -Path "vendor/components/secure_enclave/Cargo.lock" -Destination $ManifestPath
    Write-Host "    - Built and installed secure_enclave to vendor/lib64"
} else {
    Write-Host "    - Cargo not found. Skipping Rust component build."
    New-Item -ItemType File -Force -Path "$VENDOR_DIR/lib64/secure_enclave" | Out-Null
}


# --- Build Completion ---

# Display a message indicating the completion of the build process.
Write-Host "[*] Build Complete."
Write-Host "    Artifacts located in: $OUT_DIR"
