#!/usr/bin/env bash
# Shared helper functions for Antigravity shell scripts.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0;37m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ensure_sudo_session() {
    if sudo -n true 2>/dev/null; then
        log_info "Passwordless sudo detected, continuing without prompt."
    else
        log_info "Requesting sudo access for installation tasks..."
        sudo -v
    fi
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

header() {
    local text="$1"
    local width=70
    local text_len=${#text}
    local pad_left=$(( (width - text_len) / 2 ))
    local pad_right=$(( width - text_len - pad_left ))
    printf "\e[93;44m%s%s%s\e[m%b" "┌" "────────────────────────────────────────────────────────────────────────" "┐" "\n"
    printf "\e[93;44m%s %*s\e[m\e[93;44;4m%s\e[m\e[93;44m%*s%s\e[m%b" "│" "$pad_left" "" "$text" "$pad_right" "" " │" "\n"
    printf "\e[93;44m%s%s%s\e[m%b" "├" "────────────────────────────────────────────────────────────────────────" "┤" "\n"
}

option_desc() {
    printf "\e[93;44m%s\e[m%s\e[93;44m%*s\e[m%s\e[93;44m%*s%s%s\e[m%b" \
      "│ " "$1" "$((20 - ${#1}))" "" "$2" "$((50 - ${#2} - ${#3}))" "" "$3" " │" "\n"
}

footer() {
    printf "\e[93;44m%s%s%s\e[m%b" "└" "────────────────────────────────────────────────────────────────────────" "┘" "\n"
}

choose() {
    local _arr_name=$1
    eval "local _arr=(\"\${${_arr_name}[@]}\")"
    local _count=$((${#_arr[@]} / 2))
    local _sel=""

    {
        header "please invoke with:"
        for ((i=0; i<${#_arr[@]}; i+=2)); do
            option_desc "${_arr[i]}" "${_arr[i+1]}" "$((i / 2 + 1))"
        done
        footer
    } >&2

    while [ "$_sel" == "" ]; do
        read -r -p "sel: " _sel
        if [[ ! $_sel =~ ^[[:digit:]]+$ || $_sel == 0 || $_sel -gt $_count ]]; then
            _sel=""
        fi
    done

    echo "${_arr[($_sel - 1) * 2]}"
}
