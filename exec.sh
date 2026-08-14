#!/usr/bin/env bash
# Antigravity entry point.
# Use this script to run:
#   1) Installer
#   2) Metadata sync
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && cd "$SCRIPT_DIR/." || exit 1

. "$SCRIPT_DIR/helpers/common.sh"

OPTIONS=(
    "install" "install Agent/IDE"
    "sync"    "sync conversation metadata"
)

run_install() {
    exec "$SCRIPT_DIR/helpers/install.sh"
}

run_sync() {
    exec "$SCRIPT_DIR/helpers/sync.sh"
}

show_menu() {
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}              Antigravity Exec Menu               ${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "1) Install Agent/IDE"
    echo -e "2) Sync conversation metadata"
    echo -e ""
    read -r -p "Select action [1]: " selection
    selection="${selection:-1}"
    case "$selection" in
        1) run_install ;;
        2) run_sync ;;
        *) echo "Invalid selection: $selection" >&2; exit 1 ;;
    esac
}

case "${1:-}" in
    1|install) run_install ;;
    2|sync) run_sync ;;
    "" ) show_menu ;;
    * ) echo "Usage: ./exec.sh [1|2|install|sync]" >&2; exit 1 ;;
esac
