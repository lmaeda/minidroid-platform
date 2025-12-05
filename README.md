# MiniDroid プラットフォーム - セキュリティスキャンデモウォークスルー

このプロジェクトは、**Snyk**、**Syft**、**Scalibr**、**OSV-Scanner** のようなセキュリティスキャンツールをテストするために、簡略化された Android/組み込みビルド構造を模倣しています。

## ディレクトリ構造
- `system/core`: ネイティブ C++ サービス（Conan で管理）。
- `packages/apps`: Java/Kotlin アプリケーション（Maven/Gradle）。
- `vendor/components`: Go/Rust マイクロサービス。
- `system/tools`: Python システムユーティリティ。
- `external/`: Snyk Unmanaged スキャン用のサードパーティ製 C/C++ ソースとバイナリ。
- `out/`: シミュレートされた「ビルド成果物」（SBOMツールのターゲット）。

## 前提条件

以下のツールがインストールされていることを確認してください：

1.  **Snyk CLI**: `npm install -g snyk`（そして `snyk auth` を実行）
2.  **Syft**: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin`
3.  **Scalibr** (Optional): Google製のSBOM生成ツール（バイナリフィンガープリント用）。
4.  **Conan**: `pip install conan` (C/C++ パッケージ管理用)。
5.  **CycloneDX CLI**: SBOM統合用。

---

## フェーズ1：ビルドシミュレーション（自動化されたパイプライン）

実際の Android 環境では `make` がシステムイメージを作成しますが、このデモでは `build.sh` がビルドプロセス全体とセキュリティパイプラインを自動化します。

**実行コマンド (Linux/macOS):**
```bash
./build.sh
```

**`build.sh` が実行する主要なステップ:**

1.  **環境の初期化 (`init_workspace`)**:
    *   `out/target/product/generic` に Android 風のディレクトリ構造を作成します。

2.  **サードパーティ依存関係の処理**:
    *   **FFmpeg / Toybox (`process_ffmpeg`, `process_toybox`)**: ソースコードをダウンロードし、`external/lib/src` に展開します。これは後のフェーズで **Snyk Unmanaged** が C/C++ の脆弱性をスキャンするために使用されます。
    *   **Rclone (`process_rclone`)**: プリコンパイルされたバイナリをダウンロードし、`out/system/bin` に配置します。これは **Scalibr** によるバイナリスキャンの対象となります。

3.  **コンポーネントのコンパイル**:
    *   **C/C++ (`build_conan_cpp`)**: **Conan** を使用して依存関係を解決し、`conan.lock` を生成します。`native_service` をコンパイルし、ロックファイルを `out/` にコピーして SBOM ツールが検出できるようにします。
    *   **Java (`build_java_maven`, `build_java_gradle`)**: Maven と Gradle でアプリをビルドし、`pom.xml` や `gradle.lockfile` を `out/` にアーカイブします。
    *   **Python, Go, Rust**: 各言語の標準ツールでビルドし、マニフェストファイル（`requirements.txt`, `go.mod`, `Cargo.lock`）を保持します。

<img width="995" height="729" alt="Screenshot 2025-11-28 at 17 26 22" src="https://github.com/user-attachments/assets/1528fe9a-32b2-40bc-93fc-ead17a3ee77a" />


## フェーズ2：静的アプリケーションセキュリティテスト（SAST）

`build.sh` は主に SBOM と依存関係の脆弱性に焦点を当てていますが、開発者はコードをコミットする前に SAST を実行すべきです。

Snyk Code を実行して、ソースコード自体の脆弱性（バッファオーバーフローなど）をスキャンします：
```bash
snyk code test --report --project-name=minidroid --target-name=minidroid-platform --target-reference="$(git branch --show-current)" --remote-repo-url=https://github.com/lmaeda/minidroid-platform --org=${SNYK_ORG_ID}
```
**期待される結果:**
*   `system/core/native_service.c` 内の `strcpy` に起因するバッファオーバーフロー等が検出されます。


## フェーズ3：SBOM（ソフトウェア部品表）の生成と統合

`build.sh` の `generate_sboms` および `merge_sboms` 関数は、複数のツールを組み合わせて包括的な SBOM を作成します。

1.  **Scalibr によるバイナリスキャン**:
    *   `out/` ディレクトリ全体をスキャンし、バイナリのハッシュや特徴からコンポーネントを特定します（例：Rclone）。
    *   出力: `out/sboms/scalibr.json`

2.  **Syft によるファイルシステムスキャン**:
    *   `out/` ディレクトリ内のパッケージマニフェスト（`conan.lock`, `pom.xml` 等）とバイナリをスキャンします。
    *   出力: `out/sboms/syft-fs.json`

3.  **Snyk Unmanaged による C/C++ スキャン**:
    *   `external/lib/` に展開された FFmpeg や Toybox のソースコードをスキャンし、管理されていない（Unmanaged）C/C++ パッケージを特定します。
    *   出力: `out/sboms/snyk-unmanaged.json`

4.  **SBOM の統合 (Merge)**:
    *   **CycloneDX CLI** を使用して、上記3つの SBOM を `MASTER_PLATFORM_SBOM.json` に統合します。
    *   さらに `syft convert` を使用して **SPDX** 形式 (`MASTER_PLATFORM_SBOM.spdx.json`) に変換し、互換性を確保します。

<img width="1015" height="157" alt="Screenshot 2025-11-28 at 17 28 57" src="https://github.com/user-attachments/assets/04c9d88f-c836-42f6-96a9-e4a73010d995" />


## フェーズ4：SBOMの脆弱性スキャン

最後に、`build.sh` は生成されたマスター SBOM を使用して脆弱性をチェックします。

### 自動実行されるステップ (`scan_sbom`)

1.  **Snyk SBOM Test**:
    *   統合された CycloneDX および SPDX SBOM を Snyk データベースと照合します。
    *   **Log4Shell** (log4j) や 古い **FFmpeg** の脆弱性などが検出されます。
    *   結果はコンソールと JSON ファイル (`Snyk_SBOM_security_scan.json`) に出力されます。

2.  **Snyk SBOM Monitor**:
    *   SBOM のスナップショットを Snyk プラットフォームにアップロードします。
    *   これにより、将来的に新たな脆弱性が発見された場合にアラートを受け取ることができます。

**手動で確認する場合:**
```bash
# 生成されたマスターSBOMをテスト
snyk sbom test --file=out/target/product/generic/MASTER_PLATFORM_SBOM.json --experimental
```

<img width="1156" height="771" alt="Screenshot 2025-11-28 at 17 29 23" src="https://github.com/user-attachments/assets/afa675bb-703d-46b7-8384-bc9c62b9ed5f" />
<img width="903" height="767" alt="Screenshot 2025-11-28 at 17 30 38" src="https://github.com/user-attachments/assets/c78819eb-fee4-4410-abca-5756eade1b10" />

---
<br>

# MiniDroid Platform - Security Scan Demo Walkthrough

This project mimics a simplified Android/Embedded build structure to test security scanning tools like **Snyk**, **Syft**, **Scalibr**, and **OSV-Scanner**.

## Directory Structure
- `system/core`: Native C++ services (managed by Conan).
- `packages/apps`: Java/Kotlin applications (Maven/Gradle).
- `vendor/components`: Go/Rust microservices.
- `system/tools`: Python system utilities.
- `external/`: Third-party C/C++ sources and binaries for Snyk Unmanaged scanning.
- `out/`: The simulated "Build Artifact" (Target for SBOM tools).

## Prerequisites

Ensure you have the following tools installed:

1.  **Snyk CLI**: `npm install -g snyk` (and run `snyk auth`)
2.  **Syft**: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin`
3.  **Scalibr** (Optional): Google's SBOM generator for binary fingerprinting.
4.  **Conan**: `pip install conan` (for C/C++ package management).
5.  **CycloneDX CLI**: For merging SBOMs.

---

## Phase 1: The Build Simulation (Automated Pipeline)

While a real Android environment uses `make`, this demo uses `build.sh` to automate the entire build process and security pipeline.

**Run Command (Linux/macOS):**
```bash
./build.sh
```

**Key Steps Executed by `build.sh`:**

1.  **Environment Initialization (`init_workspace`)**:
    *   Creates the Android-like directory structure in `out/target/product/generic`.

2.  **Third-Party Dependency Processing**:
    *   **FFmpeg / Toybox (`process_ffmpeg`, `process_toybox`)**: Downloads and extracts source code to `external/lib/src`. This allows **Snyk Unmanaged** to scan these C/C++ sources for vulnerabilities later.
    *   **Rclone (`process_rclone`)**: Downloads a pre-compiled binary and installs it to `out/system/bin`. This serves as a target for **Scalibr**'s binary scanning.

3.  **Component Compilation**:
    *   **C/C++ (`build_conan_cpp`)**: Uses **Conan** to resolve dependencies, generating a `conan.lock` file. Compiles the `native_service` and archives the lockfile to `out/` for SBOM detection.
    *   **Java (`build_java_maven`, `build_java_gradle`)**: Builds apps and archives `pom.xml` and `gradle.lockfile` to `out/`.
    *   **Python, Go, Rust**: Builds components and preserves their respective manifests (`requirements.txt`, `go.mod`, `Cargo.lock`).

<img width="995" height="729" alt="Screenshot 2025-11-28 at 17 26 22" src="https://github.com/user-attachments/assets/1528fe9a-32b2-40bc-93fc-ead17a3ee77a" />


## Phase 2: Static Application Security Testing (SAST)

While `build.sh` focuses on SBOMs and dependencies, developers should run SAST before committing code.

Run Snyk Code to scan the source for bad coding practices (like Buffer Overflows):
```bash
snyk code test --report --project-name=minidroid --target-name=minidroid-platform --target-reference="$(git branch --show-current)" --remote-repo-url=https://github.com/lmaeda/minidroid-platform --org=${SNYK_ORG_ID}
```
**What to expect:**
*   Snyk should flag vulnerabilities in `system/core/native_service.c`, such as **"Buffer Overflow"** from `strcpy`.


## Phase 3: SBOM Generation & Consolidation

The `generate_sboms` and `merge_sboms` functions in `build.sh` combine multiple tools to create a comprehensive SBOM.

1.  **Binary Scan by Scalibr**:
    *   Scans the `out/` directory, identifying components via binary fingerprinting (e.g., Rclone).
    *   Output: `out/sboms/scalibr.json`

2.  **Filesystem Scan by Syft**:
    *   Crawls `out/` to find package manifests (including `conan.lock`, `pom.xml`) and binaries.
    *   Output: `out/sboms/syft-fs.json`

3.  **Unmanaged C/C++ Scan by Snyk**:
    *   Scans the extracted source code of FFmpeg and Toybox in `external/lib/` to identify unmanaged C/C++ packages and signatures.
    *   Output: `out/sboms/snyk-unmanaged.json`

4.  **SBOM Consolidation (Merge)**:
    *   Uses **CycloneDX CLI** to merge the three SBOMs into `MASTER_PLATFORM_SBOM.json`.
    *   Converts this master SBOM to **SPDX** format (`MASTER_PLATFORM_SBOM.spdx.json`) using `syft convert` for broader tool compatibility.

<img width="1015" height="157" alt="Screenshot 2025-11-28 at 17 28 57" src="https://github.com/user-attachments/assets/04c9d88f-c836-42f6-96a9-e4a73010d995" />


## Phase 4: SBOM Vulnerability Scanning

Finally, `build.sh` checks the generated Master SBOM against vulnerability databases.

### Automated Steps (`scan_sbom`)

1.  **Snyk SBOM Test**:
    *   Tests the merged CycloneDX and SPDX SBOMs against the Snyk Vulnerability Database.
    *   Detects issues like **Log4Shell** (log4j) or vulnerabilities in the unmanaged **FFmpeg** version.
    *   Outputs results to the console and a JSON file (`Snyk_SBOM_security_scan.json`).

2.  **Snyk SBOM Monitor**:
    *   Uploads the SBOM snapshot to the Snyk platform.
    *   Sets up continuous monitoring to alert you on future vulnerability disclosures.

**Manual Verification:**
```bash
# Test the generated Master SBOM
snyk sbom test --file=out/target/product/generic/MASTER_PLATFORM_SBOM.json --experimental
```

<img width="1156" height="771" alt="Screenshot 2025-11-28 at 17 29 23" src="https://github.com/user-attachments/assets/afa675bb-703d-46b7-8384-bc9c62b9ed5f" />
<img width="903" height="767" alt="Screenshot 2025-11-28 at 17 30 38" src="https://github.com/user-attachments/assets/c78819eb-fee4-4410-abca-5756eade1b10" />