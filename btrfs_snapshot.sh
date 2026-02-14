#!/bin/bash
# Script to take read-only Btrfs snapshots for configured subvolumes.

set -euo pipefail

# --- Source configuration and common functions ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "ERROR: config.sh not found." >&2
    exit 1
fi

if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
else
    echo "ERROR: common.sh not found." >&2
    exit 1
fi

# --- Help Function ---
show_help() {
    cat <<EOF
Usage: $(basename "$0") [-h|--help]

This script creates read-only Btrfs snapshots for configured subvolumes.
The following subvolumes are currently configured:
EOF
    for SOURCE_SUBVOL in "${SUBVOLUMES[@]}"; do
        get_snap_info "$SOURCE_SUBVOL"
        echo "  Source: $SOURCE_SUBVOL -> $SNAP_DIR/${SNAP_NAME}_<timestamp>"
    done
}

# --- Main Execution ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Simple check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

echo "--- btrfs_snapshot script execution Started: $(date) ---"

for SOURCE_SUBVOL in "${SUBVOLUMES[@]}"; do
    echo "======================================================"
    echo "Processing source subvolume: $SOURCE_SUBVOL"

    get_snap_info "$SOURCE_SUBVOL"
    mkdir -p "$SNAP_DIR"

    NEW_SNAP_NAME="${SNAP_NAME}_$(date +%Y%m%d%H%M%S)"
    NEW_SNAP_PATH="${SNAP_DIR}/${NEW_SNAP_NAME}"
    
    take_snapshot "$SOURCE_SUBVOL" "$NEW_SNAP_PATH"
done

echo "--- Script Execution Complete: $(date) ---"
