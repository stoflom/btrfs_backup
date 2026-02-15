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
Usage: $(basename "$0") [-h|--help] [-p|--preserve] [-k|--keep <num>]

This script cleans up old Btrfs snapshots (as configured in config.sh) 
both locally and on the backup destination.
It retains $KEEP (see config.sh) snapshots for each subvolume.

Options:
  -p, --preserve    Only delete snapshots from the source subvolume and NOT from the backup.
  -k, --keep <num>  Override the number of snapshots to keep (default: $KEEP from config.sh).
EOF
}

# --- Argument Parsing ---
PRESERVE_BACKUP=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--preserve)
            PRESERVE_BACKUP=true
            shift
            ;;
        -k|--keep)
            if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                KEEP="$2"
                shift 2
            else
                echo "ERROR: --keep requires a numeric argument." >&2
                exit 1
            fi
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

clean_snapshots_for_subvol() {
    local SOURCE_DIR=$1
    local DEST_DIR=$2
    local PREFIX=$3
    local KEEP_COUNT=$4

    echo "--- Cleaning snapshots for prefix: ${PREFIX} (KEEP=${KEEP_COUNT}) ---"

    # Find the latest common parent to protect it on the source
    local LATEST_COMMON=""
    if [ -d "$SOURCE_DIR" ] && [ -d "$DEST_DIR" ]; then
        LATEST_COMMON=$(get_latest_common_parent "$SOURCE_DIR" "$DEST_DIR" "$PREFIX") || LATEST_COMMON=""
    fi

    # 1. Clean Source
    if [ -d "$SOURCE_DIR" ]; then
        mapfile -t src_snaps < <(find "$SOURCE_DIR" -maxdepth 1 -mindepth 1 -type d -name "${PREFIX}_[0-9]*" | sort)
        local src_total=${#src_snaps[@]}
        
        # We want to keep KEEP_COUNT snapshots, but we also want to protect LATEST_COMMON
        if [ "$src_total" -gt "$KEEP_COUNT" ]; then
            local to_delete_count=$((src_total - KEEP_COUNT))
            local deleted=0
            
            for ((i=0; i<src_total && deleted < to_delete_count; i++)); do
                local snap="${src_snaps[i]}"
                
                if [ "$snap" = "$LATEST_COMMON" ]; then
                    echo "INFO: Protecting latest common parent on source: $snap"
                    continue
                fi
                
                echo "Deleting source snapshot: $snap"
                if btrfs subvolume delete "$snap" >/dev/null; then
                    ((deleted++))
                else
                    echo "WARNING: Failed to delete $snap" >&2
                fi
            done
            echo "INFO: $SOURCE_DIR: Deleted $deleted snapshots, kept $((src_total - deleted))."
        else
            echo "INFO: $SOURCE_DIR: $src_total snapshots found; keeping all (count <= KEEP)."
        fi
    else
        echo "INFO: Source directory $SOURCE_DIR does not exist. Skipping."
    fi

    # 2. Clean Backup
    if [ "$PRESERVE_BACKUP" = "true" ]; then
        echo "INFO: Preserve flag set. Skipping backup cleanup."
    elif [ -d "$DEST_DIR" ]; then
        mapfile -t dst_snaps < <(find "$DEST_DIR" -maxdepth 1 -mindepth 1 -type d -name "${PREFIX}_[0-9]*" | sort)
        local dst_total=${#dst_snaps[@]}
        
        if [ "$dst_total" -gt "$KEEP_COUNT" ]; then
            local to_delete=$((dst_total - KEEP_COUNT))
            echo "INFO: $DEST_DIR: Found $dst_total snapshots. Deleting $to_delete oldest."
            for ((i=0; i<to_delete; i++)); do
                echo "Deleting backup snapshot: ${dst_snaps[i]}"
                btrfs subvolume delete "${dst_snaps[i]}" >/dev/null || echo "WARNING: Failed to delete ${dst_snaps[i]}" >&2
            done
        else
            echo "INFO: $DEST_DIR: $dst_total snapshots found; keeping all (count <= KEEP)."
        fi
    else
        echo "WARNING: Backup destination $DEST_DIR not available for cleanup." >&2
    fi
}

echo "=== btrfs snapshot cleanup started: $(date) ==="

for SOURCE_SUBVOL in "${SUBVOLUMES[@]}"; do
    get_snap_info "$SOURCE_SUBVOL"
    clean_snapshots_for_subvol "$SNAP_DIR" "$BACKUP_DEST" "$SNAP_NAME" "$KEEP"
done

echo "=== cleanup complete: $(date) ==="
logger -t btrfs_snapshot_cleanup_script "Snapshot cleanup script executed on $(date)"
