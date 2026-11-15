#!/usr/bin/env bash
# Version maps and remote discovery helpers for the Antigravity installer.

IDE_VERSIONS=(
    "2.0.1"  "2.0.1-4861014005645312"
    "2.0.2"  "2.0.2-5949548972081152"
    "2.0.3"  "2.0.3-6242596486512640"
    "2.0.4"  "2.0.4-6381998290370560"
    "2.1.1"  "2.1.1-6123990880747520"
    "2.5.4"  "2.5.4-6665745933926400"
    "2.5.5"  "2.5.5-4923483625488384"
    "2.6.0"  "2.6.0-5526304964083712"
    "2.7.0"  "2.7.0-4507555968450560"
)

AGENT_VERSIONS=(
    "2.0.0"  "2.0.0-6324554176528384"
    "2.0.1"  "2.0.1-6566078776737792"
    "2.0.2"  "2.0.2-5132087175544832"
    "2.0.3"  "2.0.3-4525642893623296"
    "2.0.5"  "2.0.5-5568825152897024"
    "2.0.6"  "2.0.6-5413878570549248"
    "2.0.7"  "2.0.7-4757248736624640"
    "2.0.8"  "2.0.8-6592107553619968"
    "2.0.9"  "2.0.9-4666288509943808"
    "2.0.10" "2.0.10-5119448496078848"
    "2.0.11" "2.0.11-6560309696135168"
    "2.1.0"  "2.1.0-6066040229199872"
    "2.1.3"  "2.1.3-5208655906340864"
    "2.1.4"  "2.1.4-6481382726303744"
    "2.2.1"  "2.2.1-5287492581195776"
    "2.4.2"  "2.4.2-6711062033203200"
    "2.6.0"  "2.6.0-4603467860410368"
    "2.8.0"  "2.8.0-5810824271495168"
    "2.8.1"  "2.8.1-6512087774658560"
    "2.9.1"  "2.9.1-4871453687021568"
    "2.10.0" "2.10.0-4996573600546816"
    "2.11.0" "2.11.0-6376446768316416"
    "2.12.0" "2.12.0-5051501534642176"
    "2.15.0" "2.15.0-6576870427328512"
    "2.16.0" "2.16.0-4917332007583744"
    "2.17.0" "2.17.0-5217732355031040"
    "2.18.1" "2.18.1-4945794252537856"
    "2.19.1" "2.19.1-6046815158665216"
    "2.21.0" "2.21.0-6494382996717568"
    "2.21.1" "2.21.1-5614635819335680"
    "2.22.0" "2.22.0-5446056071266304"
    "2.23.0" "2.23.0-5238607586394112"
    "2.23.1" "2.23.1-6348059836284928"
    "2.24.0" "2.24.0-5780333019398144"
    "2.28.0" "2.28.0-6410674700681216"
    "2.29.0" "2.29.0-5723181030440960"
    "2.30.0" "2.30.0-6386428939206656"
    "2.31.0" "2.31.0-6379060755038208"
    "2.32.1" "2.32.1-6001966350991360"
)

HUB_RELEASES_API_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases"
IDE_RELEASES_API_URL="https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases"
DOWNLOAD_PAGE_URL="https://antigravity.google/download"

upsert_version_pair() {
    local array_name="$1"
    local short_version="$2"
    local full_version="$3"
    local -n versions_ref="$array_name"
    local i

    for ((i=0; i<${#versions_ref[@]}; i+=2)); do
        if [ "${versions_ref[$i]}" = "$short_version" ]; then
            versions_ref[$((i+1))]="$full_version"
            return 0
        fi
    done

    versions_ref+=("$short_version" "$full_version")
}

version_gt() {
    local a="${1%%-*}"
    local b="${2%%-*}"

    [ -n "$a" ] || return 1
    [ -n "$b" ] || return 0
    [ "$a" != "$b" ] || return 1
    [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" = "$a" ]
}

sort_version_map() {
    local array_name="$1"
    local -n versions_ref="$array_name"
    local -a sorted_pairs=()
    local i short_ver full_ver

    if [ ${#versions_ref[@]} -eq 0 ]; then
        return 0
    fi

    while IFS=' ' read -r short_ver full_ver; do
        if [ -n "$short_ver" ] && [ -n "$full_ver" ]; then
            sorted_pairs+=("$short_ver" "$full_ver")
        fi
    done < <(
        for ((i=0; i<${#versions_ref[@]}; i+=2)); do
            printf '%s %s\n' "${versions_ref[$i]}" "${versions_ref[$((i+1))]}"
        done | sort -k1,1V -k2,2V
    )

    if [ ${#sorted_pairs[@]} -gt 0 ]; then
        versions_ref=("${sorted_pairs[@]}")
    else
        versions_ref=()
    fi
}

parse_releases_json() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
items = data if isinstance(data, list) else data.get("versions", []) if isinstance(data, dict) else []
for item in items:
    if isinstance(item, dict):
        ver = str(item.get("version", "")).strip()
        exec_id = str(item.get("execution_id", "")).strip()
        if re.fullmatch(r"2\.[0-9]+\.[0-9]+", ver) and re.fullmatch(r"[0-9]+", exec_id):
            print(f"{ver}-{exec_id}")'
        return 0
    fi

    tr -d '\r\n' | grep -Eo '\{[^{}]*\}' | while IFS= read -r obj; do
        local ver eid
        ver="$(printf '%s\n' "$obj" | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"(2\.[0-9]+\.[0-9]+)".*/\1/p')"
        eid="$(printf '%s\n' "$obj" | sed -nE 's/.*"execution_id"[[:space:]]*:[[:space:]]*"([0-9]+)".*/\1/p')"
        if [ -n "$ver" ] && [ -n "$eid" ]; then
            printf '%s-%s\n' "$ver" "$eid"
        fi
    done || true
}

fetch_builds_from_releases_api() {
    local api_url="$1"
    local payload

    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    payload="$(curl -fsSL --compressed --connect-timeout 5 --max-time 15 "$api_url" 2>/dev/null || true)"
    if [ -z "$payload" ]; then
        return 0
    fi

    printf '%s' "$payload" | parse_releases_json | sort -Vu
}

fetch_all_agent_builds_from_bucket() {
    local builds page_html

    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    builds="$(fetch_builds_from_releases_api "$HUB_RELEASES_API_URL" || true)"
    if [ -z "$builds" ]; then
        page_html="$(curl -fsSL --compressed --connect-timeout 5 --max-time 15 "$DOWNLOAD_PAGE_URL" 2>/dev/null || true)"
        if [ -n "$page_html" ]; then
            builds="$(printf '%s' "$page_html" | grep -Eo 'antigravity-hub/2\.[0-9]+\.[0-9]+-[0-9]+' | sed -E 's#antigravity-hub/##' | sort -Vu || true)"
        fi
    fi

    if [ -n "$builds" ]; then
        printf '%s\n' "$builds"
    fi
}

fetch_latest_agent_build_from_bucket() {
    fetch_all_agent_builds_from_bucket | tail -n 1
}

ide_build_exists_for_any_arch() {
    local ide_build="$1"
    local ide_url
    local arch

    for arch in linux-x64 linux-arm; do
        ide_url="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${ide_build}/${arch}/Antigravity%20IDE.tar.gz"
        if curl -fsSLI --connect-timeout 5 --max-time 10 "$ide_url" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

fetch_all_ide_builds_from_api() {
    local builds page_html

    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    builds="$(fetch_builds_from_releases_api "$IDE_RELEASES_API_URL" || true)"
    if [ -z "$builds" ]; then
        page_html="$(curl -fsSL --compressed --connect-timeout 5 --max-time 15 "$DOWNLOAD_PAGE_URL" 2>/dev/null || true)"
        if [ -n "$page_html" ]; then
            builds="$(printf '%s' "$page_html" | grep -Eo 'edgedl/release2/j0qc3/antigravity/stable/2\.[0-9]+\.[0-9]+-[0-9]+' | sed -E 's#^.*/stable/##' | sort -Vu || true)"
        fi
    fi

    if [ -n "$builds" ]; then
        printf '%s\n' "$builds"
    fi
}

fetch_candidate_ide_builds() {
    local pre_fetched_api_builds="${1:-}"
    local i
    local version_source="${ANTIGRAVITY_VERSION_SOURCE:-${BASH_SOURCE[0]}}"
    local download_dir="${DOWNLOAD_DIR:-${SCRIPT_DIR:-$(pwd)}/download}"

    for ((i=1; i<${#IDE_VERSIONS[@]}; i+=2)); do
        echo "${IDE_VERSIONS[$i]}"
    done

    if [ -f "$version_source" ]; then
        if grep -q '^IDE_VERSIONS=(' "$version_source" 2>/dev/null; then
            sed -n '/^IDE_VERSIONS=(/,/^)/p' "$version_source" 2>/dev/null
        else
            cat "$version_source" 2>/dev/null
        fi | grep -Eo '"2\.[0-9]+\.[0-9]+"[[:space:]]+"2\.[0-9]+\.[0-9]+-[0-9]+"' \
           | sed -E 's/^"[^"]+"[[:space:]]+"([^"]+)".*/\1/' || true
    fi

    find "$download_dir" -maxdepth 1 -type f -name 'Antigravity_IDE_2.*.tar.gz' -printf '%f\n' 2>/dev/null \
        | sed -E 's/^Antigravity_IDE_(.*)\.tar\.gz$/\1/' || true

    if [ -n "$pre_fetched_api_builds" ]; then
        printf '%s\n' "$pre_fetched_api_builds"
    else
        fetch_all_ide_builds_from_api || true
    fi
}

refresh_ide_versions_from_remote() {
    local current_latest_build latest_verified_ide_build short_ide_version candidate_build api_builds build i found_in_local
    current_latest_build="$(latest_build_from_map "${IDE_VERSIONS[@]}")"
    api_builds="$(fetch_all_ide_builds_from_api || true)"
    latest_verified_ide_build=""

    while IFS= read -r candidate_build; do
        if [ -n "$candidate_build" ] && ide_build_exists_for_any_arch "$candidate_build"; then
            latest_verified_ide_build="$candidate_build"
            break
        fi
    done < <(fetch_candidate_ide_builds "$api_builds" | sort -rVu)

    if [ -z "$latest_verified_ide_build" ]; then
        return 0
    fi

    found_in_local="false"
    for ((i=1; i<${#IDE_VERSIONS[@]}; i+=2)); do
        if [ "${IDE_VERSIONS[$i]}" = "$latest_verified_ide_build" ]; then
            found_in_local="true"
            break
        fi
    done

    if [ "$found_in_local" != "true" ]; then
        if version_gt "$latest_verified_ide_build" "$current_latest_build"; then
            log_warn "Found newer IDE version in repository: ${latest_verified_ide_build}"
        else
            log_warn "Found IDE build in repository not present in local IDE_VERSIONS: ${latest_verified_ide_build}"
        fi
    fi

    if [ -n "$api_builds" ]; then
        while IFS= read -r build; do
            if [ -n "$build" ] && ! version_gt "$build" "$latest_verified_ide_build"; then
                upsert_version_pair "IDE_VERSIONS" "${build%%-*}" "$build"
            fi
        done < <(printf '%s\n' "$api_builds")
    fi

    short_ide_version="${latest_verified_ide_build%%-*}"
    upsert_version_pair "IDE_VERSIONS" "$short_ide_version" "$latest_verified_ide_build"
    sort_version_map "IDE_VERSIONS"
}

refresh_agent_versions_from_remote() {
    local builds current_latest_build remote_latest_build current_short remote_short build short_agent_version
    builds="$(fetch_all_agent_builds_from_bucket || true)"
    if [ -z "$builds" ]; then
        return 0
    fi

    current_latest_build="$(latest_build_from_map "${AGENT_VERSIONS[@]}")"
    remote_latest_build="$(printf '%s\n' "$builds" | tail -n 1)"
    current_short="${current_latest_build%%-*}"
    remote_short="${remote_latest_build%%-*}"

    # 1. Identify and log warnings for newer versions
    if [ -n "$remote_latest_build" ]; then
        if version_gt "$remote_short" "$current_short" || { [ "$remote_short" = "$current_short" ] && [ "$remote_latest_build" != "$current_latest_build" ]; }; then
            log_warn "Found newer Agent Manager version in repository: ${remote_latest_build}"
        fi
    fi

    # 2. Update AGENT_VERSIONS array
    while IFS= read -r build; do
        if [ -n "$build" ]; then
            short_agent_version="${build%%-*}"
            upsert_version_pair "AGENT_VERSIONS" "$short_agent_version" "$build"
        fi
    done < <(printf '%s\n' "$builds")

    sort_version_map "AGENT_VERSIONS"
}

latest_build_from_map() {
    local -a versions=("$@")
    local i

    if [ ${#versions[@]} -eq 0 ]; then
        return 0
    fi

    for ((i=0; i<${#versions[@]}; i+=2)); do
        echo "${versions[$i]} ${versions[$((i+1))]}"
    done | sort -k1,1V -k2,2V | tail -n 1 | awk '{print $2}'
}

resolve_version_from_map() {
    local input="$1"
    shift
    local -a versions=("$@")
    local i

    for ((i=0; i<${#versions[@]}; i+=2)); do
        if [ "$input" = "${versions[$i]}" ] || [ "$input" = "${versions[$((i+1))]}" ]; then
            echo "${versions[$((i+1))]}"
            return 0
        fi
    done

    echo "$input"
}

short_versions_list() {
    local -a versions=("$@")
    local i
    local out=""

    for ((i=0; i<${#versions[@]}; i+=2)); do
        if [ -z "$out" ]; then
            out="${versions[$i]}"
        else
            out="$out/${versions[$i]}"
        fi
    done

    echo "$out"
}
