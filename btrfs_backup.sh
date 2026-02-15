#!/bin/bash
# Main orchestration script for Btrfs Incremental Backups.
# Uses shared configuration and functions.

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

# --- Variables ---
SEND_RECEIVE=false
FORCE_FULL=false
SHOW_INFO=false
SHOW_CONFIG=false

# --- Usage function ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [-s|--send] [-f|--full] [-i|--info] [-c|--config] [-h|--help]

Main orchestration script for Btrfs Incremental Backups. See configuration
in config.sh.

Must be run as root.

Arguments:
  -s|--send: Enables a re-send and verification mode for the latest local snapshots.
      Does NOT create new snapshots.
  -f|--full: Forces a full send-receive (non-incremental).
  -i|--info: Display status of snapshots on both source and destination.
  -c|--config: Display the current configuration from config.sh.
  -h|--help: Display the help message and exit.
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--send)
            SEND_RECEIVE=true
            echo "Re-send/Receive mode enabled."
            shift
            ;;
        -f|--full)
            FORCE_FULL=true
            echo "Force full backup mode enabled."
            shift
            ;;
        -i|--info)
            SHOW_INFO=true
            shift
            ;;
        -c|--config)
            SHOW_CONFIG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# --- Main Execution ---

if $SHOW_CONFIG; then
    show_current_config
    exit 0
fi

# Simple check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

if $SHOW_INFO; then
    show_snapshot_info "${SUBVOLUMES[@]}" "$BACKUP_DEST"
    exit 0
fi

echo "--- btrfs_backup script execution Started: $(date) ---"

# Check if the backup destination is mounted and exists
if [ ! -d "$BACKUP_DEST" ]; then
    echo "ERROR: Backup destination $BACKUP_DEST does not exist or is not mounted. Exiting." >&2
    exit 1
fi

# Loop through the array and back up each subvolume
for SOURCE_SUBVOL in "${SUBVOLUMES[@]}"; do
    echo -e "======================================================"
    echo "Processing source subvolume: $SOURCE_SUBVOL"

    # Derive SNAP_DIR and SNAP_NAME
    get_snap_info "$SOURCE_SUBVOL"

    # Ensure the snapshot directory exists
    mkdir -p "$SNAP_DIR"

    # Get all local snapshots
    mapfile -t ALL_LOCAL_SNAPS < <(find "$SNAP_DIR" -maxdepth 1 -type d -name "${SNAP_NAME}_[0-9]*" | sort)
    
    if $SEND_RECEIVE; then
        echo "Re-send mode: syncing all missing snapshots."
        if [ ${#ALL_LOCAL_SNAPS[@]} -eq 0 ]; then
            echo "INFO: No local snapshots found for $SOURCE_SUBVOL to re-sync. Skipping."
            continue
        fi

        PREVIOUS_SNAP=""
        for SNAP in "${ALL_LOCAL_SNAPS[@]}"; do
            SNAP_NAME_BASE=$(basename "$SNAP")
            DEST_SNAP_PATH="$BACKUP_DEST/$SNAP_NAME_BASE"

            CHECK_STATUS=0
            check_snapshot_complete "$DEST_SNAP_PATH" || CHECK_STATUS=$?

            if [ $CHECK_STATUS -eq 0 ]; then
                # Already complete on destination, use as next parent
                PREVIOUS_SNAP="$SNAP"
                continue
            fi

            if [ $CHECK_STATUS -eq 2 ]; then
                echo "WARNING: Snapshot '$DEST_SNAP_PATH' is incomplete. Deleting to re-send."
                btrfs subvolume delete "$DEST_SNAP_PATH"
            else
                echo "WARNING: Snapshot '$DEST_SNAP_PATH' does not exist on backup. It will be sent."
            fi

            # If PREVIOUS_SNAP is empty (we haven't found a complete one in this loop yet),
            # try to find the latest common parent before this snapshot.
            if [ -z "$PREVIOUS_SNAP" ]; then
                PREVIOUS_SNAP=$(get_latest_common_parent "$SNAP_DIR" "$BACKUP_DEST" "$SNAP_NAME" "$SNAP") || PREVIOUS_SNAP=""
            fi

            if send_snapshot "$SNAP" "$BACKUP_DEST" "$PREVIOUS_SNAP" "$FORCE_FULL"; then
                PREVIOUS_SNAP="$SNAP"
            else
                echo "ERROR: Failed to send snapshot '$SNAP_NAME_BASE'. Stopping sync for this subvolume."
                break
            fi
        done
    else
        # Normal backup mode
        NEW_SNAP_NAME="${SNAP_NAME}_$(date +%Y%m%d%H%M%S)"
        NEW_SNAP_PATH="${SNAP_DIR}/${NEW_SNAP_NAME}"

        if take_snapshot "$SOURCE_SUBVOL" "$NEW_SNAP_PATH"; then
            # Find the best parent: latest one that exists and is complete on backup
            BEST_PARENT=$(get_latest_common_parent "$SNAP_DIR" "$BACKUP_DEST" "$SNAP_NAME" "$NEW_SNAP_PATH") || BEST_PARENT=""
            send_snapshot "$NEW_SNAP_PATH" "$BACKUP_DEST" "$BEST_PARENT" "$FORCE_FULL" || true
        fi
    fi
done

echo "--- Script Execution Complete: $(date) ---"
