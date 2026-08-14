#!/usr/bin/env bash
# Installer action used by ./exec.sh (option: install)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Directories
INSTALL_DIR_IDE="/usr/share/antigravity-ide"
INSTALL_DIR_AGENT="/usr/share/antigravity"
BIN_DIR="/usr/bin"
DESKTOP_DIR="/usr/share/applications"
ICONS_DIR="/usr/share/icons/hicolor"
BASH_COMP_DIR="/usr/share/bash-completion/completions"
MIME_DIR="/usr/share/mime/packages"
DOWNLOAD_DIR="$SCRIPT_DIR/download"
REPO_BACKUP_DIR="$SCRIPT_DIR/backup"
BACKUP_USER_STATE="${BACKUP_USER_STATE:-false}"
WARMUP_AUTO_CLOSE="${WARMUP_AUTO_CLOSE:-false}"

IDE_VERSION=""
AGENT_VERSION=""
IDE_URL=""
AGENT_URL=""

. "$SCRIPT_DIR/helpers/common.sh"
. "$SCRIPT_DIR/helpers/versions.sh"
. "$SCRIPT_DIR/helpers/process.sh"

refresh_ide_versions_from_remote
refresh_agent_versions_from_remote

# Default versions are the latest build values from the version maps above.
DEFAULT_IDE_VERSION="$(latest_build_from_map "${IDE_VERSIONS[@]}")"
DEFAULT_AGENT_VERSION="$(latest_build_from_map "${AGENT_VERSIONS[@]}")"
IDE_SHORT_VERSION_LIST="$(short_versions_list "${IDE_VERSIONS[@]}")"
AGENT_SHORT_VERSION_LIST="$(short_versions_list "${AGENT_VERSIONS[@]}")"
DEFAULT_IDE_SHORT_VERSION="${DEFAULT_IDE_VERSION%%-*}"
DEFAULT_AGENT_SHORT_VERSION="${DEFAULT_AGENT_VERSION%%-*}"

# Interactive selection if run in terminal without any parameters
if [ -t 0 ] && [ -z "$IDE_VERSION" ] && [ -z "$AGENT_VERSION" ] && [ -z "$IDE_URL" ] && [ -z "$AGENT_URL" ]; then
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}      Antigravity Installation Configuration      ${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "1) Standard Stable (IDE: ${DEFAULT_IDE_SHORT_VERSION}, Agent: ${DEFAULT_AGENT_SHORT_VERSION}) [Recommended]"
    echo -e "2) Custom Build Versions / Hashes"
    echo -e "3) Direct/General Download URLs"
    echo -e ""
    read -r -p "Select download configuration [1]: " config_choice
    config_choice="${config_choice:-1}"
    
    if [ "$config_choice" = "2" ]; then
        read -r -p "Enter Antigravity IDE version or build [$IDE_SHORT_VERSION_LIST or full hash] [$DEFAULT_IDE_VERSION]: " input_ide_ver
        IDE_VERSION="${input_ide_ver:-$DEFAULT_IDE_VERSION}"
        read -r -p "Enter Agent Manager version or build [$AGENT_SHORT_VERSION_LIST or full hash] [$DEFAULT_AGENT_VERSION]: " input_mgr_ver
        AGENT_VERSION="${input_mgr_ver:-$DEFAULT_AGENT_VERSION}"
    elif [ "$config_choice" = "3" ]; then
        read -r -p "Enter IDE Download URL [Leave blank to use default version]: " input_ide_url
        IDE_URL="$input_ide_url"
        read -r -p "Enter Agent Manager Download URL [Leave blank to use default version]: " input_mgr_url
        AGENT_URL="$input_mgr_url"
    fi
fi

# Fall back to default versions if not customized
IDE_VERSION="${IDE_VERSION:-$DEFAULT_IDE_VERSION}"
AGENT_VERSION="${AGENT_VERSION:-$DEFAULT_AGENT_VERSION}"
IDE_VERSION="$(resolve_version_from_map "$IDE_VERSION" "${IDE_VERSIONS[@]}")"
AGENT_VERSION="$(resolve_version_from_map "$AGENT_VERSION" "${AGENT_VERSIONS[@]}")"

log_info "Starting Antigravity IDE and Agent Manager installation..."
ensure_sudo_session

# 1. Terminate running processes to avoid file lock issues
log_info "Checking for running instances of Antigravity and Cockpit Tools..."
terminate_antigravity_processes "installation pre-cleanup" "1.5" "false"

# 2. Ensure required system dependencies for keyrings (secret-tool for Cockpit Tools)
if ! command -v secret-tool >/dev/null 2>&1; then
    log_info "Installing missing dependency: libsecret-tools (for secret-tool)..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y libsecret-tools || log_warn "Failed to install libsecret-tools automatically."
    fi
fi

# 3. Remove existing Antigravity package and previous install directories
log_info "Removing existing antigravity package (if installed)..."
if dpkg -s antigravity >/dev/null 2>&1; then
    sudo apt purge -y antigravity >/dev/null
    log_success "Removed antigravity package."
else
    log_info "Antigravity package is not installed, skipping package removal."
fi
log_info "Removing previous Agent Manager install directory: /usr/share/antigravity"
sudo rm -rf /usr/share/antigravity "$HOME/.local/share/antigravity"
log_info "Removing previous IDE install directory: /usr/share/antigravity-ide"
sudo rm -rf /usr/share/antigravity-ide "$HOME/.local/share/antigravity-ide"
log_info "Removing previously installed launcher, desktop, and icon artifacts..."
sudo rm -f "$BIN_DIR/antigravity" "$BIN_DIR/antigravity-ide"
sudo rm -f "$DESKTOP_DIR/antigravity.desktop" "$DESKTOP_DIR/antigravity-ide.desktop" "$DESKTOP_DIR/antigravity-ide-url-handler.desktop"
for app in antigravity antigravity-ide; do
    sudo rm -f "$ICONS_DIR/256x256/apps/${app}.png" "$ICONS_DIR/scalable/apps/${app}.svg"
done
sudo rm -f "$BASH_COMP_DIR/antigravity" "$BASH_COMP_DIR/antigravity-ide"
sudo rm -f "$MIME_DIR/antigravity-workspace.xml" "$MIME_DIR/antigravity-ide-workspace.xml"

if [ "$BACKUP_USER_STATE" = "true" ]; then
    archive_backup_dir() {
        local source_dir="$1"
        local zip_name="$2"
        local zip_path="$REPO_BACKUP_DIR/$zip_name"

        rm -f "$zip_path"
        if command -v zip >/dev/null 2>&1; then
            (
                cd "$(dirname "$source_dir")"
                zip -qry "$zip_path" "$(basename "$source_dir")"
            )
        else
            log_warn "zip is not available; keeping backup directory: $source_dir"
            return 0
        fi
        rm -rf "$source_dir"
        log_info "Archived backup to: $zip_path"
    }

    # Keep real config directories as backups before recreating/linking.
    if [ -e "$HOME/.config/Antigravity" ] && [ ! -L "$HOME/.config/Antigravity" ]; then
        backup_path="$HOME/.config/Antigravity.backup.$(date +%y%b%d'('%H:%M')' | tr '[:upper:]' '[:lower:]')"
        mv "$HOME/.config/Antigravity" "$backup_path"
        log_warn "Existing Antigravity config kept as backup: $backup_path"
        archive_backup_dir "$backup_path" "$(basename "$backup_path").zip"
    fi
    if [ -e "$HOME/.config/Antigravity IDE" ] && [ ! -L "$HOME/.config/Antigravity IDE" ]; then
        backup_path="$HOME/.config/Antigravity IDE.backup.$(date +%y%b%d'('%H:%M')' | tr '[:upper:]' '[:lower:]')"
        mv "$HOME/.config/Antigravity IDE" "$backup_path"
        log_warn "Existing Antigravity IDE config kept as backup: $backup_path"
        archive_backup_dir "$backup_path" "$(basename "$backup_path").zip"
    fi
    if [ -e "$HOME/.gemini" ] && [ ! -L "$HOME/.gemini" ]; then
        backup_path="$HOME/.gemini.backup.$(date +%y%b%d'('%H:%M')' | tr '[:upper:]' '[:lower:]')"
        mv "$HOME/.gemini" "$backup_path"
        log_warn "Existing Gemini directory kept as backup: $backup_path"
        archive_backup_dir "$backup_path" "$(basename "$backup_path").zip"
    fi
else
    log_info "BACKUP_USER_STATE=false, skipping user-state backups."
    if false; then
        log_info "Removing user-level Antigravity config state..."
        rm -rf "$HOME/.antigravity-ide"
        log_info "Removed user-state directories without backup."
        rm -rf "$HOME/.config/Antigravity" "$HOME/.config/Antigravity IDE" "$HOME/.gemini"
    fi
fi
sleep 5
# 4. Setup folders
mkdir -p "$DOWNLOAD_DIR"
sudo mkdir -p "$BIN_DIR"
sudo mkdir -p "$DESKTOP_DIR"
sudo mkdir -p "$INSTALL_DIR_IDE"
sudo mkdir -p "$INSTALL_DIR_AGENT"
sudo mkdir -p "$BASH_COMP_DIR"
sudo mkdir -p "$MIME_DIR"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_DIR="linux-x64"
elif [[ "$ARCH" == *arm* || "$ARCH" == "aarch64" ]]; then
    ARCH_DIR="linux-arm"
else
    log_error "Unsupported architecture: $ARCH"
    exit 1
fi

# 5. Install Antigravity IDE
log_info "Installing Antigravity IDE..."
IDE_ARCHIVE="$DOWNLOAD_DIR/Antigravity_IDE_${IDE_VERSION}.tar.gz"
if [ ! -f "$IDE_ARCHIVE" ]; then
    log_info "Antigravity IDE version $IDE_VERSION not found in $DOWNLOAD_DIR. Downloading..."
    if [ -z "$IDE_URL" ]; then
        IDE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${IDE_VERSION}/${ARCH_DIR}/Antigravity%20IDE.tar.gz"
    fi
    log_info "Downloading IDE from: $IDE_URL"
    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$IDE_ARCHIVE" "$IDE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$IDE_ARCHIVE" "$IDE_URL"
    else
        log_error "Neither curl nor wget found! Cannot download Antigravity IDE."
        exit 1
    fi
fi

if [ -f "$IDE_ARCHIVE" ]; then
    log_info "Extracting Antigravity IDE archive..."
    sudo tar --no-same-owner --owner=0 --group=0 -xzf "$IDE_ARCHIVE" -C "$INSTALL_DIR_IDE" --strip-components=1
fi

# 6. Install Antigravity Agent Manager
log_info "Installing Antigravity Agent Manager..."
AGENT_ARCHIVE="$DOWNLOAD_DIR/Antigravity_${AGENT_VERSION}.tar.gz"
if [ ! -f "$AGENT_ARCHIVE" ]; then
    log_info "Antigravity Agent Manager version $AGENT_VERSION not found in $DOWNLOAD_DIR. Downloading..."
    if [ -z "$AGENT_URL" ]; then
        AGENT_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${AGENT_VERSION}/${ARCH_DIR}/Antigravity.tar.gz"
    fi
    log_info "Downloading Agent Manager from: $AGENT_URL"
    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$AGENT_ARCHIVE" "$AGENT_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$AGENT_ARCHIVE" "$AGENT_URL"
    else
        log_error "Neither curl nor wget found! Cannot download Antigravity Agent Manager."
        exit 1
    fi
fi

if [ -f "$AGENT_ARCHIVE" ]; then
    log_info "Extracting Antigravity Agent Manager archive..."
    sudo tar --no-same-owner --owner=0 --group=0 -xzf "$AGENT_ARCHIVE" -C "$INSTALL_DIR_AGENT" --strip-components=1

    log_info "Installing Antigravity launcher into $INSTALL_DIR_AGENT/bin..."
    sudo mkdir -p "$INSTALL_DIR_AGENT/bin"
    sudo cp "$SCRIPT_DIR/usr/share/antigravity/bin/antigravity" "$INSTALL_DIR_AGENT/bin/antigravity"
    sudo cp "$SCRIPT_DIR/usr/share/antigravity/sync_keyring.py" "$INSTALL_DIR_AGENT/sync_keyring.py"

    # Cockpit Tools detects the Antigravity version from resources/app/product.json.
    log_info "Writing version metadata for Cockpit Tools detection..."
    AGENT_SHORT_VERSION="${AGENT_VERSION%%-*}"
    sudo mkdir -p "$INSTALL_DIR_AGENT/resources/app"
    sudo cp "$SCRIPT_DIR/usr/share/antigravity/resources/app/product.json" "$INSTALL_DIR_AGENT/resources/app/product.json"
    sudo sed -i "s/__AGENT_SHORT_VERSION__/$AGENT_SHORT_VERSION/g" "$INSTALL_DIR_AGENT/resources/app/product.json"

    # Fix Electron SUID sandbox permission issue for Agent Manager
    log_info "Configuring SUID sandbox for Agent Manager..."
    sudo chmod 4755 "$INSTALL_DIR_AGENT/chrome-sandbox" || log_warn "Could not change permissions of chrome-sandbox."
fi

# 7. Create Launch Wrappers (bypassing Electron SUID sandbox issue)
log_info "Creating executable launch wrappers..."

# Create /usr/bin/antigravity-ide symlink to the IDE launcher binary
sudo ln -sf "$INSTALL_DIR_IDE/bin/antigravity-ide" /usr/bin/antigravity-ide || log_warn "Could not create /usr/bin/antigravity-ide symlink."

# Create /usr/bin/antigravity symlink pointing to the installed launcher
sudo ln -sf "$INSTALL_DIR_AGENT/bin/antigravity" /usr/bin/antigravity || log_warn "Could not create /usr/bin/antigravity symlink."

# 8. Install Icons
log_info "Installing desktop icons..."
sudo mkdir -p "$ICONS_DIR/256x256/apps"
sudo mkdir -p "$ICONS_DIR/scalable/apps"

for app in antigravity antigravity-ide ; do
    sudo cp "$SCRIPT_DIR/usr/share/icons/hicolor/256x256/apps/antigravity.png" "$ICONS_DIR/256x256/apps/${app}.png"
    sudo cp "$SCRIPT_DIR/usr/share/icons/hicolor/scalable/apps/antigravity.svg" "$ICONS_DIR/scalable/apps/${app}.svg"
done

# 9. Create Desktop Launchers
log_info "Creating .desktop launcher files..."
sudo cp "$SCRIPT_DIR/usr/share/applications/antigravity-ide.desktop" "$DESKTOP_DIR/antigravity-ide.desktop"
sudo cp "$SCRIPT_DIR/usr/share/applications/antigravity-ide-url-handler.desktop" "$DESKTOP_DIR/antigravity-ide-url-handler.desktop"
sudo cp "$SCRIPT_DIR/usr/share/applications/antigravity.desktop" "$DESKTOP_DIR/antigravity.desktop"

# Update desktop database and icon cache
sudo update-desktop-database "$DESKTOP_DIR" || true
sudo gtk-update-icon-cache -f -t "$ICONS_DIR" 2>/dev/null || true

# 10. Install Bash Completions
log_info "Installing bash completion files..."
sudo cp "$SCRIPT_DIR/usr/share/bash-completion/completions/antigravity-ide" "$BASH_COMP_DIR/antigravity-ide"

# 11. Install MIME Packages
log_info "Installing MIME workspace package..."
sudo cp "$SCRIPT_DIR/usr/share/mime/packages/antigravity-ide-workspace.xml" "$MIME_DIR/antigravity-ide-workspace.xml"
sudo update-mime-database /usr/share/mime || true

# 12. Configure Cockpit Tools Integration
if command -v cockpit-tools >/dev/null 2>&1; then
    log_info "Configuring Cockpit Tools integration..."
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys, textwrap; exec(textwrap.dedent("""
            import json, os
            path = os.path.expanduser("~/.antigravity_cockpit/config.json")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            try:
                with open(path) as f: data = json.load(f)
            except Exception:
                data = {}
            data.update({"ws_enabled": True, "ws_port": 19528, "antigravity_app_path": "/usr/share/antigravity-ide/antigravity-ide"})
            with open(path, "w") as f: json.dump(data, f, indent=2)
        """))'
    else
        log_warn "python3 not found. Skipping Cockpit Tools auto-configuration."
    fi
fi

# 13. Initialize runtime data directories (first-run warmup)
log_info "Starting Agent and IDE briefly to initialize runtime directories..."
warmup_agent_pid=""
warmup_ide_pid=""

if command -v antigravity >/dev/null 2>&1; then
    antigravity >/dev/null 2>&1 &
    warmup_agent_pid=$!
else
    log_warn "antigravity command not found for warmup."
fi

if command -v antigravity-ide >/dev/null 2>&1; then
    antigravity-ide >/dev/null 2>&1 &
    warmup_ide_pid=$!
else
    log_warn "antigravity-ide command not found for warmup."
fi

# Wait until both installation_id files are created (max 10s).
agent_installation_id="$HOME/.gemini/antigravity/installation_id"
ide_installation_id="$HOME/.gemini/antigravity-ide/installation_id"
for _ in $(seq 1 20); do
    if [ -f "$agent_installation_id" ] && [ -f "$ide_installation_id" ]; then
        break
    fi
    sleep 0.5
done

if [ "$WARMUP_AUTO_CLOSE" = "true" ]; then
    warmup_pids="$(echo "$warmup_agent_pid $warmup_ide_pid" | xargs)"
    if [ -n "$warmup_pids" ]; then
        kill -15 $warmup_pids 2>/dev/null || true
        sleep 1
        still_running=""
        for pid in $warmup_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                still_running="$still_running $pid"
            fi
        done
        still_running="$(echo "$still_running" | xargs)"
        if [ -n "$still_running" ]; then
            kill -9 $still_running 2>/dev/null || true
        fi
    fi

    terminate_antigravity_processes "warmup cleanup" "1" "true"
else
    log_info "WARMUP_AUTO_CLOSE=false, leaving warmup-started apps running."
fi

# 14. Final success output
log_success "Installation completed successfully!"
echo -e "\n${GREEN}You can now launch the applications:${NC}"
echo -e "1. ${CYAN}Antigravity IDE${NC} (via application menu or by running: ${YELLOW}antigravity-ide${NC})"
echo -e "2. ${CYAN}Antigravity Agent Manager${NC} (via application menu or by running: ${YELLOW}antigravity${NC})"
