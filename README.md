# Antigravity Installer & Toolkit

A set of scripts for automated installation, updating, and synchronization of **Google Antigravity IDE** and **Antigravity Agent Manager** in Linux environments (Ubuntu, Debian, etc., `x86_64` and `arm64/aarch64` architectures).

---

## 📋 Table of Contents

1. [Quick Start (`./exec.sh`)](#-quick-start-execsh)
2. [Features & Capabilities](#-features--capabilities)
   - [1. Installation & Updates (Installer)](#1-installation--updates-installer)
   - [2. Metadata Synchronization (Metadata Sync)](#2-metadata-synchronization-metadata-sync)
   - [3. Version Management (Version Resolver)](#3-version-management-version-resolver)
   - [4. System Integration (Desktop & Shell Integration)](#4-system-integration-desktop--shell-integration)
3. [Environment Variables](#-environment-variables)
4. [Repository Structure](#-repository-structure)
5. [Troubleshooting](#-troubleshooting)

---

## 🚀 Quick Start (`./exec.sh`)

Run the script in your terminal:

```bash
./exec.sh
```

An interactive menu will appear:

```text
==================================================
              Antigravity Exec Menu               
==================================================
1) Install Agent/IDE
2) Sync conversation metadata

Select action [1]:
```

- **1) Install Agent/IDE** — install or update Antigravity IDE and Agent Manager.
- **2) Sync conversation metadata** — synchronize conversation history between the IDE and Hub.

---

## ⚙️ Features & Capabilities

### 1. Installation & Updates (Installer)

The `helpers/install.sh` script performs a full deployment lifecycle:

- **Automated Download & Extraction**:
  - Downloads official Antigravity IDE and Agent Manager archives directly from Google Cloud Storage / EdgeDL.
  - Saves archives to the local `download/` cache directory to avoid redundant downloads.
  - Automatically detects your OS architecture (`linux-x64` or `linux-arm`).
- **Interactive Build Configuration Selection**:
  1. **Standard Stable (Recommended)** — automatically resolves and downloads the latest stable releases.
  2. **Custom Build Versions / Hashes** — allows specifying a short version (e.g. `2.5.5` for IDE or `2.8.1` for Agent) or a full build hash.
  3. **Direct Download URLs** — option to provide direct URLs to custom archives.
- **Safe Process Cleanup**:
  - Gracefully terminates running Antigravity and Cockpit Tools processes (`SIGTERM` -> `SIGKILL`) before installation, avoiding file-locking conflicts without affecting parent sessions.
- **Electron Sandbox Configuration**:
  - Sets appropriate SUID permissions `chmod 4755` on `chrome-sandbox`, resolving common Electron startup errors on Linux.
- **Warmup Initialization**:
  - Launches a brief background process post-installation to initialize environment directories and `installation_id` files in `~/.gemini/`.

---

### 2. Metadata Synchronization (Metadata Sync)

The `helpers/sync.py` script (invoked via menu option 2) resolves conversation history desynchronization between clients:

- **Two-Format Merging**:
  - **Standalone Hub**: `~/.gemini/antigravity/agyhub_summaries_proto.pb` (binary Protobuf wire format).
  - **IDE Storage**: `~/.config/Antigravity/User/globalStorage/state.vscdb` (SQLite database, `antigravityUnifiedStateSync.trajectorySummaries` and `unifiedStateSync.trajectorySummaries` Base64 keys).
- **Parsing & Normalization**:
  - Decodes Protobuf Varints and field tags.
  - Deduplicates conversation entries by trajectory UUID.
  - Writes the synchronized state back to both storage locations.
- **Automatic Backups**:
  - Creates `.bak` backup files for every modified file before writing changes.

---

### 3. Version Management (Version Resolver)

The `helpers/versions.sh` script:
- Maintains a built-in mapping table between version numbers and build hashes.
- Queries the `https://storage.googleapis.com/antigravity-public` bucket and download pages to discover new releases in real time.

---

### 4. System Integration (Desktop & Shell Integration)

The installer provides comprehensive system integration:

| Component | Location | Description |
| :--- | :--- | :--- |
| **Binary Symlinks** | `/usr/bin/antigravity`, `/usr/bin/antigravity-ide` | Global terminal command access |
| **Desktop Entries** | `/usr/share/applications/*.desktop` | GNOME/KDE/XFCE application menu integration and URL handler registration |
| **Icons** | `/usr/share/icons/hicolor/` | PNG (256x256) and vector SVG icons |
| **Bash Completion** | `/usr/share/bash-completion/completions/antigravity-ide` | Command-line auto-completion for bash |
| **MIME Types** | `/usr/share/mime/packages/antigravity-ide-workspace.xml` | Workspace file association with the IDE |
| **Cockpit Tools** | `~/.antigravity_cockpit/config.json` | Automatic WebSocket port (19528) and path configuration when Cockpit Tools is present |

---

## 🔧 Environment Variables

You can customize script behavior using environment variables during execution:

```bash
# Create zip backups of user configs before installation
BACKUP_USER_STATE=true ./exec.sh

# Automatically close applications after the warmup check completes
WARMUP_AUTO_CLOSE=true ./exec.sh
```

| Variable | Default | Description |
| :--- | :--- | :--- |
| `BACKUP_USER_STATE` | `false` | When `true`, archives `~/.config/Antigravity*` and `~/.gemini` directories into the `backup/` folder. |
| `WARMUP_AUTO_CLOSE` | `false` | When `true`, forcefully terminates applications launched during the warmup initialization phase. |

---

## 📁 Repository Structure

```text
.
├── exec.sh                   # Main interactive menu
├── README.md                 # Documentation
├── download/                 # Cache directory for downloaded tar.gz archives
├── backup/                   # Directory for backup zip archives
├── helpers/
│   ├── common.sh             # Color logging, sudo session keep-alive
│   ├── install.sh            # IDE and Agent Manager installer script
│   ├── process.sh            # Process discovery and termination logic
│   ├── sync.py               # Low-level Protobuf / SQLite synchronization
│   ├── sync.sh               # Runner wrapper for sync.py
│   └── versions.sh           # Version mapping and Google Storage resolver
└── usr/                      # System file templates
    └── share/
        ├── applications/     # .desktop files
        ├── bash-completion/  # Shell auto-completion scripts
        ├── icons/            # Application icons
        └── mime/             # Workspace MIME types
```

---

## ❓ Troubleshooting

1. **IDE fails to launch due to sandbox error (SUID Sandbox)**:
   The installer automatically executes `chmod 4755 /usr/share/antigravity/chrome-sandbox`. If the issue persists, run `./exec.sh` and select the install option again to restore proper permissions.

2. **Recent conversations not showing up in IDE or Standalone Agent**:
   Run `./exec.sh` and select option `2) Sync conversation metadata`. The script will read existing conversations and merge them into an up-to-date state.

3. **Launching Installed Applications**:
   - IDE: `antigravity-ide` (or via your desktop application menu)
   - Agent Manager: `antigravity` (or via your desktop application menu)
