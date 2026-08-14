#!/usr/bin/env bash
# Wrapper entrypoint: executes metadata synchronization logic implemented in sync.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/sync.py" "$@"
