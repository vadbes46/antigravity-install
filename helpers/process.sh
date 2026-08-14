#!/usr/bin/env bash
# Shared process termination logic for Antigravity install/warmup flows.

get_ancestors() {
    local pid=$1
    while [ -n "$pid" ] && [ "$pid" -ne 0 ]; do
        echo "$pid"
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || echo "")
    done
}

terminate_antigravity_processes() {
    local context="${1:-installation}"
    local sleep_after_term="${2:-1.5}"
    local include_local_ide="${3:-false}"

    local ancestor_pids pids filtered_pids cmdline exe_path is_ancestor still_running
    ancestor_pids=$(get_ancestors $$ | tr '\n' ' ' | xargs)
    log_info "Excluding ancestor process IDs: $ancestor_pids"

    pids=$(pgrep -f "antigravity|antigravity-ide|cockpit-tools" 2>/dev/null || true)
    filtered_pids=""

    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            is_ancestor=false
            for ancestor in $ancestor_pids; do
                if [ "$pid" -eq "$ancestor" ] 2>/dev/null; then
                    is_ancestor=true
                    break
                fi
            done
            if [ "$is_ancestor" = true ]; then
                continue
            fi

            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "")
            exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || echo "")

            if [[ "$cmdline" == *"install.sh"* ]]; then
                continue
            fi

            if [ "$include_local_ide" = "true" ]; then
                if [[ "$cmdline" != *"/usr/share/antigravity"* \
                      && "$cmdline" != *"/usr/share/antigravity-ide"* \
                      && "$cmdline" != *"/home/"*".local/share/antigravity-ide"* \
                      && "$cmdline" != *"cockpit-tools"* \
                      && "$exe_path" != *"/usr/share/antigravity/"* \
                      && "$exe_path" != *"/usr/share/antigravity-ide/"* \
                      && "$exe_path" != *"/home/"*".local/share/antigravity-ide/"* \
                      && "$exe_path" != *"cockpit-tools"* ]]; then
                    continue
                fi
            else
                if [[ "$cmdline" != *"/usr/share/antigravity"* \
                      && "$cmdline" != *"/usr/share/antigravity-ide"* \
                      && "$cmdline" != *"cockpit-tools"* \
                      && "$exe_path" != *"/usr/share/antigravity/"* \
                      && "$exe_path" != *"/usr/share/antigravity-ide/"* \
                      && "$exe_path" != *"cockpit-tools"* ]]; then
                    continue
                fi
            fi

            filtered_pids="$filtered_pids $pid"
        fi
    done

    filtered_pids=$(echo $filtered_pids | xargs)
    if [ -n "$filtered_pids" ]; then
        log_warn "Stopping running Antigravity/Cockpit processes for $context (PIDs: $filtered_pids)..."
        kill -15 $filtered_pids 2>/dev/null || true
        sleep "$sleep_after_term"

        still_running=""
        for pid in $filtered_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                still_running="$still_running $pid"
            fi
        done
        still_running=$(echo $still_running | xargs)
        if [ -n "$still_running" ]; then
            log_warn "Force killing remaining processes for $context (PIDs: $still_running)..."
            kill -9 $still_running 2>/dev/null || true
        fi
    fi
}
