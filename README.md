# MiniDroid プラットフォーム - セキュリティスキャンデモウォークスルー

このプロジェクトは、**Snyk**、**Syft**、**OSV-Scanner** のようなセキュリティスキャンツールをテストするために、簡略化された Android/組み込みビルド構造を模倣しています。

## ディレクトリ構造
- `system/core`: ネイティブ C++ サービス。
- `packages/apps`: Java/Kotlin アプリケーション。
- `vendor/components`: Go/Rust マイクロサービス。
- `system/tools`: Python システムユーティリティ。
- `out/`: シミュレートされた「ビルド成果物」（Syft/OSV のターゲット）。

## 前提条件

以下のツールがインストールされていることを確認してください：

1.  **Snyk CLI**: `npm install -g snyk`（そして `snyk auth` を実行）
2.  **Syft**: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin`
3.  **OSV-Scanner**: `go install github.com/google/osv-scanner/cmd/osv-scanner@latest`（またはバイナリダウンロード経由）

---

## フェーズ1：ビルドシミュレーション

実際の Android 環境では、`source build/envsetup.sh` と `make` がシステムイメージを作成します。ここでは、その簡略版を模倣します。このリポジトリには、Linux/macOS用の `build_system.sh` と Windows用の `build_system.ps1` の2つのビルドスクリプトが含まれています。これらのスクリリプトは、Java、C/C++、Python、Go、およびRustで書かれたさまざまなコンポーネントをコンパイルし、ビルド成果物を `out/` ディレクトリに配置します。

お使いのオペレーティングシステムに適したビルドスクリプトを実行して、`out/` にファイルシステム成果物を生成します。

**Linux/macOS (Bash):**
```bash
./build_system.sh
```

**Windows (PowerShell):**
```powershell
./build_system.ps1
```
*出力:* Java、C++、Python、Go、および Rust のコンパイル、および `out/target/product/generic` への成果物のインストールを示す、より詳細なログが表示されるはずです。これは、実際のビルド出力ディレクトリをシミュレートしています。

***重要:*** ビルドスクリプトは、`pom.xml`、`go.mod`、`Cargo.toml` などのパッケージマニフェストファイルを `out/` ディレクトリに意図的にコピーします。これにより、`Syft` のようなSBOMツールが、最終的なビルド成果物に含まれるすべてのソフトウェアコンポーネントを正確に検出できるようになります。
<img width="995" height="729" alt="Screenshot 2025-11-28 at 17 26 22" src="https://github.com/user-attachments/assets/1528fe9a-32b2-40bc-93fc-ead17a3ee77a" />
<img width="1269" height="712" alt="Screenshot 2025-11-28 at 17 26 48" src="https://github.com/user-attachments/assets/860f4b6c-203f-4485-8ef5-ac28495256e8" />


## フェーズ2：静的アプリケーションセキュリティテスト（SAST）

コンパイルされた OS を見る前に、ソースコードに悪いコーディングプラクティス（バッファオーバーフローなど）がないかスキャンしましょう。

Snyk Code を実行して、ソースの脆弱性をスキャンし、Snyk に結果を報告します：
```bash
snyk code test --report --project-name=minidroid --target-name=minidroid-platform --target-reference="$(git branch --show-current)" --remote-repo-url=https://github.com/lmaeda/minidroid-platform --org=${SNYK_ORG_ID}
```
**期待されること:**
*   Snyk は `system/core/native_service.c` の脆弱性をフラグ付けするはずです。
*   `strcpy` の使用に関する **"Unchecked Input for Loop Condition"** や **"Buffer Overflow"** のような警告を探してください。
*   このコマンドは、結果を Snyk プラットフォームに報告し、指定されたプロジェクト名、ターゲット名、ブランチ参照、リモートリポジトリ URL、および組織 ID で関連付けます。
<img width="1425" height="580" alt="Screenshot 2025-11-28 at 17 28 30" src="https://github.com/user-attachments/assets/0180a96c-98c9-4553-97f4-4aec610725a3" />


## フェーズ3：SBOM（ソフトウェア部品表）の生成

次に、`out/` ディレクトリを検査します。これは、デバイスにフラッシュされる最終的なファイルシステムを表します。SBOM を生成して、その中のすべてのソフトウェアコンポーネントをカタログ化する必要があります。

Syft を使用して SBOM を生成します：
```bash
# 「ビルドされた」イメージ（out ディレクトリ）をスキャンして、最終的な OS に何が含まれているかを確認します。
syft dir:./out/ -o cyclonedx-json --file minidroid.sbom.json
```
**何が起こったか？**
*   Syft はシミュレートされたシステムディレクトリをクロールしました。
*   ビルド中にそこにコピーされた `pom.xml`、`requirements.txt`、`go.mod`、`Cargo.toml` などのパッケージマニフェストファイルを見つけました。
*   これらすべてのコンポーネントをリストした CycloneDX JSON ファイルを作成しました。
<img width="1015" height="157" alt="Screenshot 2025-11-28 at 17 28 57" src="https://github.com/user-attachments/assets/04c9d88f-c836-42f6-96a9-e4a73010d995" />

## フェーズ4：SBOMの脆弱性スキャン

これで、ソフトウェアの「成分」リストを既知の脆弱性データベースと照合できます。

### オプションA：Google OSV-Scanner を使用する

Google の OSV データベースは、オープンソースの脆弱性に対して優れています。

```bash
osv-scanner --sbom minidroid.sbom.json
```
**期待されること:**
*   `log4j-core`（バージョン 2.14.1）をフラグ付けするはずです。
*   `requests`（バージョン 2.19.0）をフラグ付けするはずです。
*   これらのコンポーネントを OSV データベースと照合し、関連する脆弱性を見つけます。
<img width="1156" height="771" alt="Screenshot 2025-11-28 at 17 29 23" src="https://github.com/user-attachments/assets/afa675bb-703d-46b7-8384-bc9c62b9ed5f" />

### オプションB：Snyk sbom を使用する

SBOM を Snyk にインポートすると、オープンソースの脆弱性を分析し、経時的に追跡できます。

```bash
snyk sbom test --experimental --file=minidroid.sbom.json
```
**期待されること:**
*   Snyk は SBOM にリストされているパッケージを特定します。
*   `log4j` の重大な **Log4Shell** 脆弱性を表示します。
*   詳細情報と修正アドバイスについては、Snyk 脆弱性データベースへのリンクを提供します。
<img width="903" height="767" alt="Screenshot 2025-11-28 at 17 30 38" src="https://github.com/user-attachments/assets/c78819eb-fee4-4410-abca-5756eade1b10" />


### オプションC：Snyk sbom を使用して SBOM を監視する

Snyk に SBOM を監視させると、長期的に依存関係の脆弱性を追跡し、新しい脆弱性が発見されたときにアラートを受け取ることができます。

```bash
snyk sbom monitor --org=${SNYK_ORG_ID} --experimental --file=minidroid.sbom.json
```
**期待されること:**
*   このコマンドは、`minidroid.sbom.json` ファイルによって定義されたプロジェクトを Snyk プラットフォームで監視するように設定します。
*   Snyk が新しい脆弱性を発見すると、関連するプロジェクトに対してアラートが送信されます。
<img width="1105" height="604" alt="Screenshot 2025-11-28 at 17 31 09" src="https://github.com/user-attachments/assets/a27f1998-435b-4951-8ac6-286103faf3bd" />

<img width="1268" height="766" alt="Screenshot 2025-11-28 at 17 20 21" src="https://github.com/user-attachments/assets/80dfdf6a-462e-4a33-933b-7708c4d2d0f3" />


---
<br>

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

In a real Android environment, `source build/envsetup.sh` and `make` create the system image. We will mimic a simplified version of this process. This repository includes two build scripts: `build_system.sh` for Linux/macOS and `build_system.ps1` for Windows. These scripts compile the various components written in Java, C/C++, Python, Go, and Rust, and place the build artifacts into the `out/` directory.

Run the build script appropriate for your operating system to generate the filesystem artifacts in `out/`:

**For Linux/macOS (Bash):**
```bash
./build_system.sh
```

**For Windows (PowerShell):**
```powershell
./build_system.ps1
```
*Output:* You should see logs indicating it is compiling C++, Java, Go, and Rust, and installing the artifacts into `out/target/product/generic`. This simulates a real build output directory.

***Note:*** The build scripts are intentionally configured to copy package manifest files (e.g., `pom.xml`, `go.mod`, `Cargo.toml`, etc.) into the `out/` directory. This is crucial for ensuring that SBOM tools like `Syft` can accurately discover all software components included in the final build artifact.
<img width="995" height="729" alt="Screenshot 2025-11-28 at 17 26 22" src="https://github.com/user-attachments/assets/1528fe9a-32b2-40bc-93fc-ead17a3ee77a" />
<img width="1269" height="712" alt="Screenshot 2025-11-28 at 17 26 48" src="https://github.com/user-attachments/assets/860f4b6c-203f-4485-8ef5-ac28495256e8" />


## Phase 2: Static Application Security Testing (SAST)

Before we look at the compiled OS, let's scan the source code for bad coding practices (like Buffer Overflows).

Run Snyk Code to scan the source for vulnerabilities and report the results to Snyk:
```bash
snyk code test --report --project-name=minidroid --target-name=minidroid-platform --target-reference="$(git branch --show-current)" --remote-repo-url=https://github.com/lmaeda/minidroid-platform --org=${SNYK_ORG_ID}
```
**What to expect:**
*   Snyk should flag a vulnerability in `system/core/native_service.c`.
*   Look for warnings like **"Unchecked Input for Loop Condition"** or **"Buffer Overflow"** regarding the use of `strcpy`.
*   This command will report the results to the Snyk platform, associating them with the specified project name, target name, branch reference, remote repository URL, and organization ID.
<img width="1425" height="580" alt="Screenshot 2025-11-28 at 17 28 30" src="https://github.com/user-attachments/assets/0180a96c-98c9-4553-97f4-4aec610725a3" />


## Phase 3: Generating the SBOM (Software Bill of Materials)

Now we'll inspect the `out/` directory. This represents the final file system that would be flashed onto a device. We need to catalog all the software components inside it by generating an SBOM.

Generate the SBOM using Syft:
```bash
# Scan the "built" image (the out directory ) to see what ended up in the final OS.
syft dir:./out/ -o cyclonedx-json --file minidroid.sbom.json
```
**What just happened?**
*   Syft crawled the simulated system directory.
*   It found the package manifests (`pom.xml`, `requirements.txt`, `go.mod`, `Cargo.toml`, etc.) that were copied there during the build.
*   It created a CycloneDX JSON file listing all these components.
<img width="1015" height="157" alt="Screenshot 2025-11-28 at 17 28 57" src="https://github.com/user-attachments/assets/04c9d88f-c836-42f6-96a9-e4a73010d995" />

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
<img width="1156" height="771" alt="Screenshot 2025-11-28 at 17 29 23" src="https://github.com/user-attachments/assets/afa675bb-703d-46b7-8384-bc9c62b9ed5f" />

### Option B: Using Snyk Open Source

Importing the SBOM into Snyk allows you to analyze open-source vulnerabilities and track them over time.

```bash
snyk sbom test --experimental --file=minidroid.sbom.json
```
**What to expect:**
*   Snyk will identify the packages listed in the SBOM.
*   It will show the critical **Log4Shell** vulnerability in `log4j`.
*   It provides a link to the Snyk Vulnerability Database for detailed information and remediation advice.
<img width="903" height="767" alt="Screenshot 2025-11-28 at 17 30 38" src="https://github.com/user-attachments/assets/c78819eb-fee4-4410-abca-5756eade1b10" />

### Option C: Using Snyk sbom to Monitor SBOM

Allow Snyk to monitor your SBOM for long-term dependency vulnerability tracking and receive alerts when new vulnerabilities are disclosed.

```bash
snyk sbom monitor --org=${SNYK_ORG_ID} --experimental --file=minidroid.sbom.json
```
**What to expect:**
*   This command will set up monitoring for the project defined by the `minidroid.sbom.json` file on the Snyk platform.
*   Snyk will send alerts for the associated project when new vulnerabilities are found.
<img width="1105" height="604" alt="Screenshot 2025-11-28 at 17 31 09" src="https://github.com/user-attachments/assets/a27f1998-435b-4951-8ac6-286103faf3bd" />

<img width="1268" height="766" alt="Screenshot 2025-11-28 at 17 20 21" src="https://github.com/user-attachments/assets/80dfdf6a-462e-4a33-933b-7708c4d2d0f3" />
