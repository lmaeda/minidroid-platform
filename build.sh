#!/bin/bash
# ==============================================================================
# SCRIPT: build.sh
# CONTEXT: Runs inside the minidroid-platformv2 directory
# DESCRIPTION:
#   Automates the build process for the Minidroid platform, manages 3rd-party
#   dependencies, and executes a comprehensive security scanning pipeline.
#
# KEY FUNCTIONS:
#   1. Environment Setup: Creates output directories.
#   2. Artifact Processing: Downloads/Compiles binaries (FFmpeg, Toybox, Rclone, etc.).
#   3. Build: Compiles Java (Maven/Gradle), C/C++ (Conan), Python, Go, and Rust components.
#   4. SBOM Generation: Generates Software Bill of Materials using Syft, Scalibr, and Snyk.
#   5. SBOM Consolidation: Merges all SBOMs into a master record.
#   6. Security Scan: Scans the master SBOM for vulnerabilities using Snyk.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
# This ensures that any failure in the pipeline halts execution immediately,
# preventing cascading errors or invalid build artifacts.
set -e

# ==============================================================================
# GLOBAL CONFIGURATION
# ==============================================================================
# Output directory structure matching Android build standards
# Validated against: out/target/product/generic
OUT_DIR="out/target/product/generic"
SYSTEM_DIR="$OUT_DIR/system"
VENDOR_DIR="$OUT_DIR/vendor"
SBOM_DIR="$OUT_DIR/sboms"

# Dependency Versions (Centralized for easy maintenance)
FFMPEG_VERSION="5.1.4"
TOYBOX_VERSION="0.8.7"
RCLONE_VERSION="v1.66.0"

# Directories for external dependencies
# Validated against: external/bin, external/lib, external/src
EXTERNAL_BIN="external/bin"
EXTERNAL_LIB="external/lib"
EXTERNAL_LIB_SRC="external/lib/src"
EXTERNAL_SRC="external/src"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# Function: init_workspace
# Purpose:  Prepares the build environment by creating necessary directory trees.
#           Ensures that all target paths exist before copying artifacts.
# ------------------------------------------------------------------------------
function init_workspace() {
    echo "========================================================"
    echo "[Init] Initializing Workspace"
    echo "========================================================"
    echo "    - Creating output directories in: $OUT_DIR"
    
    # Create standard Android partition structure (system, vendor)
    # This matches the layout expected by subsequent build steps and scanners.
    # - bin: Executable binaries
    # - framework/app: Java/Android application packages
    # - lib/lib64: Shared libraries
    # - etc/manifests: Stores build manifests (pom.xml, package.json) for SBOM tools
    mkdir -p "$SYSTEM_DIR"/bin
    mkdir -p "$SYSTEM_DIR"/framework
    mkdir -p "$SYSTEM_DIR"/app
    mkdir -p "$SYSTEM_DIR"/lib
    mkdir -p "$SYSTEM_DIR"/etc/manifests
    mkdir -p "$VENDOR_DIR"/bin
    mkdir -p "$VENDOR_DIR"/lib64
    mkdir -p "$EXTERNAL_BIN"
    mkdir -p "$EXTERNAL_LIB"
    mkdir -p "$EXTERNAL_SRC"
    
    # Create directories for SBOM outputs and external dependency storage
    mkdir -p "$SBOM_DIR"
}

# ------------------------------------------------------------------------------
# Function: process_ffmpeg
# Purpose:  Downloads and unpacks FFmpeg source code.
# Reason:   We need the unmanaged C++ source code extracted so that Snyk 
#           can perform a code-level scan for vulnerabilities.
# ------------------------------------------------------------------------------
function process_ffmpeg() {
    echo "[+] Processing Unmanaged C++ (FFmpeg ${FFMPEG_VERSION})..."
    local archive="ffmpeg-${FFMPEG_VERSION}.tar.gz"
    local url="https://ffmpeg.org/releases/${archive}"
    # Target path: external/lib/ffmpeg-5.1.4.tar.gz
    local dest="${EXTERNAL_LIB}/${archive}"
    # Extraction path: external/lib/src/ffmpeg_src
    local src_dir="${EXTERNAL_LIB_SRC}/ffmpeg_src"

    # Clean up previous artifacts
    [ -d "$src_dir" ] && rm -rf "$src_dir"
    [ -f "$SYSTEM_DIR/bin/ffmpeg_custom" ] && rm "$SYSTEM_DIR/bin/ffmpeg_custom"

    mkdir -p "$src_dir"

    # 1. Download if missing
    # Checks if the tarball already exists in external/lib to avoid re-downloading
    if [ ! -f "$dest" ]; then
        echo "    - Downloading source..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract for scanning
    #    We strip the top-level directory (--strip-components=1) to keep paths clean in the SBOM.
    #    This source extraction allows 'snyk sbom --unmanaged' to detect code vulnerabilities.
    echo "    - Extracting to $src_dir..."
    tar -xzf "$dest" -C "$src_dir" --strip-components=1

    # 3. Simulate Build
    #    In a real scenario, we would run ./configure && make here.
    #    Touching a file simulates the binary creation for this demo at system/bin/ffmpeg_custom.
    touch "$SYSTEM_DIR/bin/ffmpeg_custom"
    echo "    - Build artifact simulated at $SYSTEM_DIR/bin/ffmpeg_custom"
}

# ------------------------------------------------------------------------------
# Function: process_toybox
# Purpose:  Downloads and unpacks Toybox source code.
# Reason:   Similar to FFmpeg, unmanaged source code is required for 
#           accurate vulnerability scanning.
# ------------------------------------------------------------------------------
function process_toybox() {
    echo "[+] Processing Unmanaged C++ (Toybox ${TOYBOX_VERSION})..."
    local archive="toybox-${TOYBOX_VERSION}.tar.gz"
    local url="http://landley.net/toybox/downloads/${archive}"
    # Target path: external/lib/toybox-0.8.7.tar.gz
    local dest="${EXTERNAL_LIB}/${archive}"
    # Extraction path: external/lib/src/toybox_src
    local src_dir="${EXTERNAL_LIB_SRC}/toybox_src"

    # Clean up previous artifacts
    [ -d "$src_dir" ] && rm -rf "$src_dir"
    [ -f "$SYSTEM_DIR/bin/toybox_custom" ] && rm "$SYSTEM_DIR/bin/toybox_custom"

    mkdir -p "$src_dir"

    # 1. Download if missing
    if [ ! -f "$dest" ]; then
        echo "    - Downloading source..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract for scanning
    #    Unpacks source to external/lib/src/toybox_src for analysis
    echo "    - Extracting to $src_dir..."
    tar -xzf "$dest" -C "$src_dir" --strip-components=1

    # 3. Simulate Build
    #    Simulate compilation artifact at system/bin/toybox_custom
    touch "$SYSTEM_DIR/bin/toybox_custom"
    echo "    - Build artifact simulated at $SYSTEM_DIR/bin/toybox_custom"
}

# ------------------------------------------------------------------------------
# Function: process_rclone
# Purpose:  Downloads and installs the Rclone binary.
# Reason:   This is a pre-compiled binary integration. We unzip it to allow
#           scanners to see the binary and license files, then install it.
# ------------------------------------------------------------------------------
function process_rclone() {
    echo "[+] Processing Android Common (Rclone ${RCLONE_VERSION})..."
    local zip_name="rclone-${RCLONE_VERSION}-linux-amd64.zip"
    local folder_name="rclone-${RCLONE_VERSION}-linux-amd64"
    local url="https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/${zip_name}"
    # Target path: external/lib/rclone-v1.66.0-linux-amd64.zip
    local dest="${EXTERNAL_LIB}/${zip_name}"
    # Extraction path: external/lib/src/rclone_bin_dir
    local extract_base="${EXTERNAL_LIB_SRC}/rclone_bin_dir"

    # Clean up previous artifacts
    [ -d "$extract_base" ] && rm -rf "$extract_base"
    [ -f "${EXTERNAL_BIN}/rclone_bin" ] && rm "${EXTERNAL_BIN}/rclone_bin"
    [ -f "$SYSTEM_DIR/bin/rclone_bin" ] && rm "$SYSTEM_DIR/bin/rclone_bin"

    # 1. Download if missing
    if [ ! -f "$dest" ]; then
        echo "    - Downloading binary archive..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract
    #    Required for Snyk to analyze the binary signature if supported,
    #    and for general file visibility.
    echo "    - Extracting to $extract_base..."
    unzip -q -o "$dest" -d "$extract_base"

    # 3. Install
    local binary_src="${extract_base}/${folder_name}/rclone"
    local binary_local="${EXTERNAL_BIN}/rclone_bin"
    
    if [ -f "$binary_src" ]; then
        # Copy to external/rclone_bin (local reference)
        cp "$binary_src" "$binary_local"
        # Copy to system image (final artifact) at system/bin/rclone_bin
        cp "$binary_local" "$SYSTEM_DIR/bin/rclone_bin"
        echo "    - Installed rclone to system/bin"
    else
        echo "    ! ERROR: Rclone binary not found at $binary_src"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function: build_conan_cpp
# Purpose:  Manages C/C++ dependencies via Conan and compiles native services.
# ------------------------------------------------------------------------------
function build_conan_cpp() {
    echo "[+] Building C/C++ Native Services (Conan)..."
    
    # Clean up previous artifacts
    [ -f "$SYSTEM_DIR/bin/native_service" ] && rm "$SYSTEM_DIR/bin/native_service"
    [ -d "$SYSTEM_DIR/etc/manifests/native_service" ] && rm -rf "$SYSTEM_DIR/etc/manifests/native_service"

    # Prerequisite Check
    if ! command -v gcc &> /dev/null; then
        echo "    ! GCC not found. Skipping compilation."
        touch "$SYSTEM_DIR/bin/native_service"
        return
    fi

    # Conan Dependency Management
    # Validated against: system/core/conanfile.txt
    if command -v conan &> /dev/null; then
        echo "    - Resolving dependencies with Conan..."
        # Create a default profile if it doesn't exist
        conan profile detect --force > /dev/null 2>&1 || true
        
        # Compatibility fix for newer Apple Clang versions in Conan default profile
        if [ -f "$HOME/.conan2/profiles/default" ]; then
             sed -i.bak 's/compiler.version=17/compiler.version=16/' "$HOME/.conan2/profiles/default"
        fi
        
        # Install dependencies defined in system/core/conanfile.txt
        # 'conan lock create' generates a reproducible dependency graph
        # 'conan install' downloads the packages
        (cd system/core && conan lock create conanfile.txt > /dev/null && conan install conanfile.txt > /dev/null)
    else
        echo "    ! Conan not found. Skipping dependency installation."
    fi
    
    # Compilation
    # Compiles system/core/native_service.c -> system/bin/native_service
    echo "    - Compiling native_service.c..."
    gcc system/core/native_service.c -o "$SYSTEM_DIR/bin/native_service"
    
    # Manifest Preservation (For SBOM correlation)
    # Copies conanfile.txt and conan.lock to system/etc/manifests/native_service
    # This allows SBOM tools to associate the binary with its dependencies
    echo "    - Archiving build manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/native_service"
    [ -f "system/core/conanfile.txt" ] && cp system/core/conanfile.txt "$SYSTEM_DIR/etc/manifests/native_service/"
    [ -f "system/core/conan.lock" ] && cp system/core/conan.lock "$SYSTEM_DIR/etc/manifests/native_service/"
}

# ------------------------------------------------------------------------------
# Function: build_java_maven
# Purpose:  Builds the 'Launcher' application using Maven.
# ------------------------------------------------------------------------------
function build_java_maven() {
    echo "[+] Building Java App: Launcher (Maven)..."
    
    # Clean up previous artifacts
    [ -f "$SYSTEM_DIR/app/Launcher.jar" ] && rm "$SYSTEM_DIR/app/Launcher.jar"
    [ -d "$SYSTEM_DIR/etc/manifests/Launcher" ] && rm -rf "$SYSTEM_DIR/etc/manifests/Launcher"

    if ! command -v mvn &> /dev/null; then
        echo "    ! Maven not found. Skipping build."
        touch "$SYSTEM_DIR/app/Launcher.jar"
        return
    fi

    # Build
    # Executes mvn package in packages/apps/Launcher
    # -q: Quiet output
    # -DskipTests: Skip running tests to speed up the build for this script
    echo "    - Running mvn package..."
    (cd packages/apps/Launcher && mvn package -q -DskipTests)
    
    # Install
    # Copies resulting JAR to system/app/Launcher.jar
    echo "    - Installing JAR..."
    cp packages/apps/Launcher/target/*.jar "$SYSTEM_DIR/app/Launcher.jar"
    
    # Manifest Preservation
    # Copies pom.xml to system/etc/manifests/Launcher for SBOM analysis
    echo "    - Archiving pom.xml..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/Launcher"
    cp packages/apps/Launcher/pom.xml "$SYSTEM_DIR/etc/manifests/Launcher/pom.xml"
}

# ------------------------------------------------------------------------------
# Function: build_java_gradle
# Purpose:  Builds the 'Settings' application using Gradle.
# ------------------------------------------------------------------------------
function build_java_gradle() {
    echo "[+] Building Java App: Settings (Gradle)..."
    
    # Clean up previous artifacts
    [ -f "$SYSTEM_DIR/app/Settings.jar" ] && rm "$SYSTEM_DIR/app/Settings.jar"
    [ -d "$SYSTEM_DIR/etc/manifests/Settings" ] && rm -rf "$SYSTEM_DIR/etc/manifests/Settings"

    if ! command -v gradle &> /dev/null; then
        echo "    ! Gradle not found. Skipping build."
        touch "$SYSTEM_DIR/app/Settings.jar"
        return
    fi

    # Build
    # Executes gradle build in packages/apps/Settings
    # --write-locks: Ensures gradle.lockfile is generated/updated for dependency pinning
    echo "    - Running gradle build..."
    (cd packages/apps/Settings && gradle build --write-locks -q -x test)
    
    # Install
    # Copies resulting JAR to system/app/Settings.jar
    # '|| true' handles cases where build might fail or produce different outputs in demo env
    echo "    - Installing JAR..."
    cp packages/apps/Settings/build/libs/*.jar "$SYSTEM_DIR/app/Settings.jar" || true
    
    # Manifest Preservation
    # Copies build.gradle and gradle.lockfile to system/etc/manifests/Settings
    # Essential for accurate dependency tracking in the SBOM
    echo "    - Archiving build.gradle and locks..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/Settings"
    cp packages/apps/Settings/build.gradle "$SYSTEM_DIR/etc/manifests/Settings/build.gradle"
    [ -f packages/apps/Settings/gradle.lockfile ] && cp packages/apps/Settings/gradle.lockfile "$SYSTEM_DIR/etc/manifests/Settings/gradle.lockfile"
}

# ------------------------------------------------------------------------------
# Function: build_python
# Purpose:  Sets up a Python virtual environment and installs tooling.
# Reason:   Ensures reproducible Python tool execution and captures 
#           dependencies (requirements.txt) for the SBOM.
# ------------------------------------------------------------------------------
function build_python() {
    echo "[+] Building Python Tools..."
    
    # Clean up previous artifacts
    [ -f "$SYSTEM_DIR/bin/sys_monitor.py" ] && rm "$SYSTEM_DIR/bin/sys_monitor.py"
    [ -d "$SYSTEM_DIR/etc/manifests/sys_monitor" ] && rm -rf "$SYSTEM_DIR/etc/manifests/sys_monitor"

    # Environment Setup
    # Creates/uses .venv in the root directory to isolate dependencies
    if [ ! -f "./.venv/bin/activate" ]; then
        echo "    - Creating virtual environment (.venv)..."
        python3 -m venv ./.venv
    fi
    
    echo "    - Activating virtual environment..."
    source "./.venv/bin/activate"
    
    # Install Dependencies
    # Installs from system/tools/requirements.txt
    echo "    - Installing requirements..."
    pip install -q -r system/tools/requirements.txt
    
    # Install Script
    # Copies system/tools/sys_monitor.py to system/bin/sys_monitor.py
    echo "    - Installing sys_monitor.py..."
    cp system/tools/sys_monitor.py "$SYSTEM_DIR/bin/sys_monitor.py"
    
    # Manifest Preservation
    # Archives requirements.txt to system/etc/manifests/sys_monitor
    echo "    - Archiving requirements.txt..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/sys_monitor"
    cp system/tools/requirements.txt "$SYSTEM_DIR/etc/manifests/sys_monitor/requirements.txt"
}

# ------------------------------------------------------------------------------
# Function: build_go
# Purpose:  Compiles the 'netdaemon' microservice using Go.
# ------------------------------------------------------------------------------
function build_go() {
    echo "[+] Building Go Service: netdaemon..."
    
    # Clean up previous artifacts
    [ -f "$SYSTEM_DIR/bin/netdaemon" ] && rm "$SYSTEM_DIR/bin/netdaemon"
    [ -d "$SYSTEM_DIR/etc/manifests/netdaemon" ] && rm -rf "$SYSTEM_DIR/etc/manifests/netdaemon"

    if ! command -v go &> /dev/null; then
        echo "    ! Go not found. Skipping build."
        touch "$SYSTEM_DIR/bin/netdaemon"
        return
    fi

    echo "    - Compiling..."
    # Go mod tidy ensures go.sum is up to date for SBOM accuracy
    # Builds vendor/services/netdaemon -> system/bin/netdaemon
    (cd vendor/services/netdaemon && go mod tidy && go build -o "../../../$SYSTEM_DIR/bin/netdaemon" .)
    
    # Manifest Preservation
    # Copies go.mod and go.sum to system/etc/manifests/netdaemon
    echo "    - Archiving go.mod/go.sum..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/netdaemon"
    cp vendor/services/netdaemon/go.mod "$SYSTEM_DIR/etc/manifests/netdaemon/"
    cp vendor/services/netdaemon/go.sum "$SYSTEM_DIR/etc/manifests/netdaemon/"
}

# ------------------------------------------------------------------------------
# Function: build_rust
# Purpose:  Compiles the 'secure_enclave' service using Rust/Cargo.
# ------------------------------------------------------------------------------
function build_rust() {
    echo "[+] Building Rust Service: secure_enclave..."
    
    # Clean up previous artifacts
    [ -f "$VENDOR_DIR/lib64/secure_enclave" ] && rm "$VENDOR_DIR/lib64/secure_enclave"
    [ -d "$SYSTEM_DIR/etc/manifests/secure_enclave" ] && rm -rf "$SYSTEM_DIR/etc/manifests/secure_enclave"

    if ! command -v cargo &> /dev/null; then
        echo "    ! Cargo not found. Skipping build."
        touch "$VENDOR_DIR/lib64/secure_enclave"
        return
    fi

    echo "    - Compiling (Release mode)..."
    # Builds vendor/services/enclave in release mode
    # --quiet: Reduces build output noise
    (cd vendor/services/enclave && cargo build --release --quiet)
    
    # Install
    # Copies binary to vendor/lib64/secure_enclave
    echo "    - Installing binary..."
    cp vendor/services/enclave/target/release/secure-enclave "$VENDOR_DIR/lib64/secure_enclave"
    
    # Manifest Preservation
    # Copies Cargo.toml and Cargo.lock to system/etc/manifests/secure_enclave
    echo "    - Archiving Cargo.toml/lock..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/secure_enclave"
    cp vendor/services/enclave/Cargo.toml "$SYSTEM_DIR/etc/manifests/secure_enclave/"
    cp vendor/services/enclave/Cargo.lock "$SYSTEM_DIR/etc/manifests/secure_enclave/"
}

# ------------------------------------------------------------------------------
# Function: generate_sboms
# Purpose:  Orchestrates the generation of SBOMs from various sources.
# Tools:
#   - Scalibr: Scans the final directory (binary fingerprinting).
#   - Syft: Scans the directory structure (filesystem analysis).
#   - Snyk: Scans unmanaged source code (C/C++).
# ------------------------------------------------------------------------------
function generate_sboms() {
    echo "========================================================"
    echo "[Phase 2] SBOM Generation"
    echo "========================================================"

    # 1. Scalibr (Google's SBOM Generator & Scanner)
    #    Scans the build output directory to identify packages.
    #    Generates: out/target/product/generic/sboms/scalibr.json
    echo "[Security] Running Scalibr (OSV-Scanner)..."
    if command -v scalibr &> /dev/null; then
        [ -f "$SBOM_DIR/scalibr.json" ] && rm "$SBOM_DIR/scalibr.json"
        scalibr --root="$OUT_DIR" -o cdx-json="$SBOM_DIR/scalibr.json"
        
        # Post-processing: Fix missing component types if necessary to ensure compliance
        # Some scanners might produce SBOMs with empty "type" fields, which violates spec.
        if [ -f "$SBOM_DIR/scalibr.json" ]; then
             sed 's/"type": ""/"type": "application"/' "$SBOM_DIR/scalibr.json" > "$SBOM_DIR/scalibr.json.tmp" && \
             mv "$SBOM_DIR/scalibr.json.tmp" "$SBOM_DIR/scalibr.json"
             echo "    - Scalibr SBOM generated: $SBOM_DIR/scalibr.json"
        fi
    else
        echo "    ! Scalibr not found. Skipping."
    fi

    # 2. Syft (Anchore)
    #    Generates a file-system based SBOM of the output directory.
    #    Generates: out/target/product/generic/sboms/syft-fs.json
    echo "[Security] Running Syft..."
    if command -v syft &> /dev/null; then
        [ -f "$SBOM_DIR/syft-fs.json" ] && rm "$SBOM_DIR/syft-fs.json"
        syft dir:$OUT_DIR -o cyclonedx-json@1.6 > "$SBOM_DIR/syft-fs.json"
        echo "    - Syft SBOM generated: $SBOM_DIR/syft-fs.json"
    else
        echo "    ! Syft not found. Skipping."
    fi

    # 3. Snyk (Unmanaged C++)
    #    Scans the 'external' directory where we unpacked the C++ sources.
    #    Generates: out/target/product/generic/sboms/snyk-unmanaged.json
    echo "[Security] Running Snyk Unmanaged (C++)..."
    [ -f "$SBOM_DIR/snyk-unmanaged.json" ] && rm "$SBOM_DIR/snyk-unmanaged.json"
    
    if [ ! -f "$SBOM_DIR/snyk-unmanaged.json" ]; then
        # Use '|| true' to prevent build failure if vulnerability found (we want to report, not stop yet).
        # We explicitly scan the 'external' directory because binary scanners often miss 
        # vulnerabilities in unmanaged C/C++ source code before it is compiled.
        snyk sbom --unmanaged --format=cyclonedx1.6+json --all-projects --version=0.0.1 ./external/lib/ > "$SBOM_DIR/snyk-unmanaged.json" || true
        echo "    - Snyk Unmanaged SBOM generated: $SBOM_DIR/snyk-unmanaged.json"
    else
        echo "    ! Snyk SBOM exists already. No action taken."
    fi
}

# ------------------------------------------------------------------------------
# Function: merge_sboms
# Purpose:  Consolidates individual tool SBOMs into a single Master SBOM.
# Tool:     CycloneDX CLI
# ------------------------------------------------------------------------------
function merge_sboms() {
    echo "========================================================"
    echo "[Phase 3] SBOM Consolidation"
    echo "========================================================"
    
    local master_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.json"
    local input_files=("$SBOM_DIR/syft-fs.json" "$SBOM_DIR/snyk-unmanaged.json" "$SBOM_DIR/scalibr.json")
    
    # Filter for files that actually exist
    # This prevents errors if one of the scanners failed or wasn't installed.
    local valid_inputs=()
    for f in "${input_files[@]}"; do
        [ -f "$f" ] && valid_inputs+=("$f")
    done

    # Uses cyclonedx-cli to 
    # 1. merge all partial SBOMs into one master record
    # 2. prepare SBOM in SPDX format v2.3 for Snyk scanning
    if command -v cyclonedx &> /dev/null; then
        # 1. Merge all partial SBOMs into one master record in CycloneDX format
        echo "[Merge] merging ${#valid_inputs[@]} SBOM files..."
        
        [ -f "$master_sbom" ] && rm "$master_sbom"

        if [ ${#valid_inputs[@]} -gt 0 ]; then
            cyclonedx merge \
                --input-files "${valid_inputs[@]}" \
                --output-file "$master_sbom" \
                --output-format json \
                --output-version v1_6
            echo "[Success] MASTER SBOM created at: $master_sbom"
        else
            echo "[Error] No valid SBOMs to merge."
        fi

        # 2. Transform the CycloneDX master SBOM to SPDX SBOM file (v2.3 JSON format)
        #    SPDX is often required for compliance and interoperability with other security tools.
        echo "[Transform] transform the CycloneDX SBOM to SPDX SBOM file..."
        local spdx_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.spdx.json"
        
        # remove existing SPDX SBOM if exists
        if [ -f "$spdx_sbom" ]; then
            rm "$spdx_sbom"
        fi

        # Convert CycloneDX to SPDX using syft
        syft convert "$master_sbom" -o spdx-json > "$spdx_sbom"
        
        # FIX: Ensure SPDX compliance for Snyk (fix missing names)
        # Some conversion tools may produce valid JSON but missing required fields for Snyk's parser.
        # This script patches the generated SPDX file to ensure compatibility.
        if [ -f "fix_spdx_sbom.py" ]; then
             echo "[Fix] Running SPDX SBOM Fixer..."
             python3 fix_spdx_sbom.py "$spdx_sbom" "$master_sbom"
        fi

        echo "[Success] SPDX SBOM created at: $spdx_sbom"
    else
        echo "[Merge & Transform] cyclonedx-cli not found. Falling back to simple concatenation (Demo mode)."
        # Fallback: Just take the Syft one if available, or the first valid one
        if [ ${#valid_inputs[@]} -gt 0 ]; then
             cp "${valid_inputs[0]}" "$master_sbom"
             echo "[Warning] Performed simple copy of ${valid_inputs[0]}. Install cyclonedx-cli for true merging."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: scan_sbom
# Purpose:  Submits the Master SBOM to Snyk for vulnerability analysis.
# ------------------------------------------------------------------------------
function scan_sbom() {
    echo "========================================================"
    echo "[Phase 4] Security Scan & Monitor"
    echo "========================================================"
    
    local master_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.json"
    local spdx_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.spdx.json"
    local report_file="$OUT_DIR/Snyk_SBOM_security_scan.json"
    local report_spdx_file="$OUT_DIR/Snyk_SBOM_security_scan.spdx.json"
    
    # Submits the consolidated SBOM to Snyk for analysis
    if [ -f "$master_sbom" ]; then
        echo "    - Testing CycloneDX SBOM for vulnerabilities..."
        [ -f "$report_file" ] && rm "$report_file"

        # 1. Test (Output JSON for machine reading)
        #    Saves scan results to out/target/product/generic/Snyk_SBOM_security_scan.json
        #    '--experimental' is required for some SBOM testing features.
        snyk sbom test --file="$master_sbom" --experimental --json > "$report_file" || true
        
        # 2. Test (Output to console for human reading)
        snyk sbom test --file="$master_sbom" --experimental || true

        # 3. Monitor (Upload to Snyk Dashboard)
        #    Uploads the SBOM snapshot to the Snyk Web UI for ongoing monitoring.
        #    --target-reference: Tags the uploaded snapshot with the current Git branch for traceability.
        #    --remote-repo-url: Links the SBOM to the remote repository for better context in Snyk.
        echo "    - Uploading snapshot to Snyk CDX SBOM Monitor..."
        snyk sbom monitor \
            --org=c649b690-a033-490d-b6ca-b9e80bc1832b \
            --file="$master_sbom" \
            --experimental \
            --target-reference="$(git branch --show-current)" \
            --remote-repo-url="https://github.com/lmaeda/minidroid-platformv2" || true
    else
        echo "    ! Master SBOM not found. Skipping scan."
    fi

    # Additionally, scan the SPDX SBOM if it exists
    if [ -f "$spdx_sbom" ]; then
        echo "    - Testing SPDX SBOM for vulnerabilities..."
        [ -f "$report_spdx_file" ] && rm "$report_spdx_file"
        # 1. Test (Output JSON for machine reading)
        #    Saves scan results to out/target/product/generic/Snyk_SBOM_security_scan.json
        snyk sbom test --file="$spdx_sbom" --experimental --json > "$report_spdx_file" || true
        
        # 2. Test (Output to console for human reading)
        snyk sbom test --file="$spdx_sbom" --experimental || true

        # 3. Monitor (Upload to Snyk Dashboard)
        #    Uploads the SBOM snapshot to the Snyk Web UI for ongoing monitoring.
        #    --target-reference: Tags the uploaded snapshot with the current Git branch for traceability.
        #    --remote-repo-url: Links the SBOM to the remote repository for better context in Snyk.
        echo "    - Uploading snapshot to Snyk SPDX SBOM Monitor..."
        snyk sbom monitor \
            --org=c649b690-a033-490d-b6ca-b9e80bc1832b \
            --file="$spdx_sbom" \
            --experimental \
            --target-reference="$(git branch --show-current)" \
            --remote-repo-url="https://github.com/lmaeda/minidroid-platformv2/spdx/" || true
    else
        echo "    ! SPDX SBOM not found. Skipping scan."
    fi
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================
function main() {
    init_workspace
    
    echo "========================================================"
    echo "[Phase 1] Build & Prepare Artifacts"
    echo "========================================================"
    
    # Process 3rd Party Binaries/Sources
    # Handles downloading, extraction, and simulated building of external dependencies like FFmpeg, Toybox, and Rclone.
    process_ffmpeg
    process_toybox
    process_rclone
    
    # Build System Components
    # Compiles various platform components written in C/C++, Java (Maven/Gradle), Python, Go, and Rust.
    build_conan_cpp
    build_java_maven
    build_java_gradle
    build_python
    build_go
    build_rust
    
    # Security Pipeline
    # Orchestrates the generation, consolidation, and scanning of Software Bill of Materials (SBOMs).
    generate_sboms
    merge_sboms
    scan_sbom
    
    echo "========================================================"
    echo "[Done] Build and Scan Complete."
    echo "========================================================"
}

# Execute Main
main
