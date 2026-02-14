#!/bin/bash
# Cleanup old Btrfs snapshots locally and on backup destination.

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

This script cleans up old Btrfs snapshots (as configured in config.sh) 
both locally and on the backup destination.
It retains $KEEP (see config.sh) snapshots for each subvolume.
EOF
}

# --- Argument Parsing ---
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

clean_snapshots_in_dir() {
    local TARGET_DIR=$1
    local SNAP_NAME_PREFIX=$2
    local KEEP_COUNT=$3

    if [ ! -d "$TARGET_DIR" ]; then
        echo "INFO: Directory $TARGET_DIR does not exist. Skipping."
        return 0
    fi

    # Gather snapshots sorted (old -> new)
    mapfile -t snaps < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d -name "${SNAP_NAME_PREFIX}_[0-9]*" | sort)

    local total=${#snaps[@]}
    if [ "$total" -le "$KEEP_COUNT" ]; then
        echo "INFO: $TARGET_DIR: $total snapshots found; keeping all (KEEP=${KEEP_COUNT})."
        return 0
    fi

    local to_delete_count=$((total - KEEP_COUNT))
    echo "INFO: $TARGET_DIR: $total snapshots found; deleting $to_delete_count oldest."

    for ((i=0; i<to_delete_count; i++)); do
        snap="${snaps[i]}"
        echo "Deleting snapshot: $snap"
        if ! btrfs subvolume delete "$snap" > /dev/null; then
            echo "WARNING: Failed to delete snapshot $snap." >&2
        fi
    done
}

echo "=== btrfs snapshot cleanup started: $(date) ==="

for SOURCE_SUBVOL in "${SUBVOLUMES[@]}"; do
    get_snap_info "$SOURCE_SUBVOL"
    
    echo "Processing $SOURCE_SUBVOL -> snapshot name prefix: $SNAP_NAME"
    
    # Clean local snapshots
    clean_snapshots_in_dir "$SNAP_DIR" "$SNAP_NAME" "$KEEP"
    
    # Clean backup snapshots
    if [ -d "$BACKUP_DEST" ]; then
        clean_snapshots_in_dir "$BACKUP_DEST" "$SNAP_NAME" "$KEEP"
    else
        echo "WARNING: Backup destination $BACKUP_DEST not available for cleanup." >&2
    fi
done

echo "=== cleanup complete: $(date) ==="
logger -t btrfs_snapshot_cleanup_script "Snapshot cleanup script executed on $(date)"
