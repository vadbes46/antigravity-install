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
)

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

fetch_all_agent_builds_from_bucket() {
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    {
        curl -fsSL --compressed "https://antigravity.google/download" 2>/dev/null || true
        curl -fsSL "https://storage.googleapis.com/antigravity-public?prefix=antigravity-hub/&delimiter=/" 2>/dev/null || true
    } \
        | grep -Eo 'antigravity-hub/2\.[0-9]+\.[0-9]+-[0-9]+' \
        | sed -E 's#antigravity-hub/##' \
        | sort -V
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
        if curl -fsSLI "$ide_url" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

fetch_candidate_ide_builds() {
    local i
    local version_source="${ANTIGRAVITY_VERSION_SOURCE:-${BASH_SOURCE[0]}}"
    local download_dir="${DOWNLOAD_DIR:-${SCRIPT_DIR:-$(pwd)}/download}"

    for ((i=1; i<${#IDE_VERSIONS[@]}; i+=2)); do
        echo "${IDE_VERSIONS[$i]}"
    done

    grep -Eo '"2\.[0-9]+\.[0-9]+"[[:space:]]+"2\.[0-9]+\.[0-9]+-[0-9]+"' "$version_source" 2>/dev/null \
        | sed -E 's/^"[^"]+"[[:space:]]+"([^"]+)".*/\1/' || true

    find "$download_dir" -maxdepth 1 -type f -name 'Antigravity_IDE_2.*.tar.gz' -printf '%f\n' 2>/dev/null \
        | sed -E 's/^Antigravity_IDE_(.*)\.tar\.gz$/\1/' || true

    curl -fsSL --compressed "https://antigravity.google/download" 2>/dev/null \
        | grep -Eo 'edgedl/release2/j0qc3/antigravity/stable/2\.[0-9]+\.[0-9]+-[0-9]+' \
        | sed -E 's#^.*/stable/##' || true
}

refresh_ide_versions_from_remote() {
    local current_latest_build latest_verified_ide_build short_ide_version candidate_build i
    current_latest_build="$(latest_build_from_map "${IDE_VERSIONS[@]}")"
    latest_verified_ide_build=""

    while IFS= read -r candidate_build; do
        if ide_build_exists_for_any_arch "$candidate_build"; then
            latest_verified_ide_build="$candidate_build"
        fi
    done < <(fetch_candidate_ide_builds | sort -Vu)

    if [ -z "$latest_verified_ide_build" ]; then
        return 0
    fi

    short_ide_version="${latest_verified_ide_build%%-*}"
    for ((i=1; i<${#IDE_VERSIONS[@]}; i+=2)); do
        if [ "${IDE_VERSIONS[$i]}" = "$latest_verified_ide_build" ]; then
            upsert_version_pair "IDE_VERSIONS" "$short_ide_version" "$latest_verified_ide_build"
            return 0
        fi
    done

    if [ "$latest_verified_ide_build" != "$current_latest_build" ]; then
        log_warn "Found newer IDE version in repository: ${latest_verified_ide_build}"
    else
        log_warn "Found IDE build in repository not present in local IDE_VERSIONS: ${latest_verified_ide_build}"
    fi
    upsert_version_pair "IDE_VERSIONS" "$short_ide_version" "$latest_verified_ide_build"
}

refresh_agent_versions_from_remote() {
    local builds
    builds="$(fetch_all_agent_builds_from_bucket || true)"
    if [ -z "$builds" ]; then
        return 0
    fi

    # 1. Identify and log warnings for new versions/branches
    local branches branch remote_latest local_latest i full_ver
    branches="$(echo "$builds" | cut -d. -f1,2 | sort -u)"
    
    while IFS= read -r branch; do
        if [ -n "$branch" ]; then
            remote_latest="$(echo "$builds" | grep -E "^${branch//./\.}\." | tail -n 1)"
            
            # Find local latest build for this branch in AGENT_VERSIONS
            local local_branch_builds=()
            for ((i=0; i<${#AGENT_VERSIONS[@]}; i+=2)); do
                full_ver="${AGENT_VERSIONS[$((i+1))]}"
                if [[ "$full_ver" =~ ^$branch\. ]]; then
                    local_branch_builds+=("${AGENT_VERSIONS[$i]}" "$full_ver")
                fi
            done
            local_latest="$(latest_build_from_map "${local_branch_builds[@]}")"
            
            if [ -n "$remote_latest" ] && [ "$remote_latest" != "$local_latest" ]; then
                log_warn "Found newer Agent Manager version in repository: ${remote_latest}"
            fi
        fi
    done < <(echo "$branches")

    # 2. Update AGENT_VERSIONS array
    local build short_agent_version
    while IFS= read -r build; do
        if [ -n "$build" ]; then
            short_agent_version="${build%%-*}"
            upsert_version_pair "AGENT_VERSIONS" "$short_agent_version" "$build"
        fi
    done < <(echo "$builds")
}

latest_build_from_map() {
    local -a versions=("$@")
    local i

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
