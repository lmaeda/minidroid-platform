# MiniDroid Platform - Security Scan Demo Walkthrough

This project mimics a simplified Android/Embedded build structure to test security scanning tools like **Snyk**, **Syft**, and **OSV-Scanner**.

## Directory Structure
- `system/core`: Native C++ services.
- `packages/apps`: Java/Kotlin applications.
- `vendor/components`: Go/Rust microservices.
- `system/tools`: Python system utilities.
- `out/`: The simulated "Build Artifact" (Target for Syft/OSV).

## Prerequisites

Ensure you have the following tools installed:

1.  **Snyk CLI**: `npm install -g snyk` (and run `snyk auth`)
2.  **Syft**: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin`
3.  **OSV-Scanner**: `go install github.com/google/osv-scanner/cmd/osv-scanner@latest` (or via binary download)

---

## Phase 1: The Build Simulation

In a real Android environment, `source build/envsetup.sh` and `make` create the system image. We will mimic a simplified version of this process.

Run the build script to generate the filesystem artifacts in `out/`:
```bash
./build_system.sh
```
*Output:* You should see logs indicating it is "Compiling" C++ and "Installing" JAR/Python artifacts into `out/target/product/generic/system`. This simulates a real build output directory.

## Phase 2: Static Application Security Testing (SAST)

Before we look at the compiled OS, let's scan the source code for bad coding practices (like Buffer Overflows).

Run Snyk Code to scan the source for vulnerabilities:
```bash
snyk code test
```
**What to expect:**
*   Snyk should flag a vulnerability in `system/core/native_service.c`.
*   Look for warnings like **"Unchecked Input for Loop Condition"** or **"Buffer Overflow"** regarding the use of `strcpy`.

## Phase 3: Generating the SBOM (Software Bill of Materials)

Now we'll inspect the `out/` directory. This represents the final file system that would be flashed onto a device. We need to catalog all the software components inside it by generating an SBOM.

Generate the SBOM using Syft:
```bash
# Scan the "built" image (the out directory) to see what ended up in the final OS.
syft dir:./out/target/product/generic/system -o cyclonedx-json --file minidroid.sbom.json
```
**What just happened?**
*   Syft crawled the simulated system directory.
*   It found the `pom.xml` (renamed), `requirements.txt`, and `go.mod` files that were copied there during the build.
*   It created a CycloneDX JSON file listing all these components.

## Phase 4: Vulnerability Scanning the SBOM

Now we can check our list of software "ingredients" against known vulnerability databases.

### Option A: Using Google OSV-Scanner

Google's OSV database is excellent for open-source vulnerabilities.

```bash
osv-scanner --sbom minidroid.sbom.json
```
**What to expect:**
*   It should flag `log4j-core` (Version 2.14.1).
*   It should flag `requests` (Version 2.19.0).
*   It matches these components against the OSV database to find associated vulnerabilities.

### Option B: Using Snyk Open Source

Importing the SBOM into Snyk allows you to analyze open-source vulnerabilities and track them over time.

```bash
snyk sbom test --file=minidroid.sbom.json
```
**What to expect:**
*   Snyk will identify the packages listed in the SBOM.
*   It will show the critical **Log4Shell** vulnerability in `log4j`.
*   It provides a link to the Snyk Vulnerability Database for detailed information and remediation advice.