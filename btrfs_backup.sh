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

# --- Usage function ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [-s|--send] [-f|--full] [-h|--help]

Main orchestration script for Btrfs Incremental Backups. See configuration
in config.sh.

Must be run as root.

Arguments:
  -s|--send: Enables a re-send and verification mode for the latest local snapshots.
      Does NOT create new snapshots.
  -f|--full: Forces a full send-receive (non-incremental).
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

# Simple check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# --- Main Execution ---

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

    # Find the most recent snapshot
    LATEST_SNAPSHOT=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${SNAP_NAME}_[0-9]*" | sort | tail -n 1)
    
    if $SEND_RECEIVE; then
        echo "Re-send mode: attempting to send latest existing snapshot."
        if [ -z "$LATEST_SNAPSHOT" ]; then
            echo "INFO: No local snapshots found for $SOURCE_SUBVOL to re-send. Skipping."
            continue
        fi

        SNAPSHOT_TO_SEND="$LATEST_SNAPSHOT"
        SNAPSHOT_TO_SEND_NAME=$(basename "$SNAPSHOT_TO_SEND")
        DEST_SNAP_PATH="$BACKUP_DEST/$SNAPSHOT_TO_SEND_NAME"

        # Check for completeness
        CHECK_STATUS=0
        check_snapshot_complete "$DEST_SNAP_PATH" || CHECK_STATUS=$?

        if [ $CHECK_STATUS -eq 0 ]; then
            echo "INFO: Snapshot '$DEST_SNAP_PATH' appears complete. Skipping."
            continue
        elif [ $CHECK_STATUS -eq 2 ]; then
            echo "WARNING: Snapshot '$DEST_SNAP_PATH' is incomplete. Deleting to re-send."
            btrfs subvolume delete "$DEST_SNAP_PATH"
        else
            echo "WARNING: Snapshot '$DEST_SNAP_PATH' does not exist on backup. It will be sent."
        fi

        # Find the parent of the snapshot we are trying to send
        PARENT_OF_SNAPSHOT=$(find "$SNAP_DIR" -maxdepth 1 -type d -name "${SNAP_NAME}_[0-9]*" | sort | grep -B 1 "$SNAPSHOT_TO_SEND" | head -n 1)
        if [ "$PARENT_OF_SNAPSHOT" = "$SNAPSHOT_TO_SEND" ]; then
            PARENT_OF_SNAPSHOT=""
        fi

        send_snapshot "$SNAPSHOT_TO_SEND" "$BACKUP_DEST" "$PARENT_OF_SNAPSHOT" "$FORCE_FULL" || true
    else
        # Normal backup mode
        NEW_SNAP_NAME="${SNAP_NAME}_$(date +%Y%m%d%H%M%S)"
        NEW_SNAP_PATH="${SNAP_DIR}/${NEW_SNAP_NAME}"

        if take_snapshot "$SOURCE_SUBVOL" "$NEW_SNAP_PATH"; then
            # Use LATEST_SNAPSHOT (found before taking the new one) as parent
            send_snapshot "$NEW_SNAP_PATH" "$BACKUP_DEST" "$LATEST_SNAPSHOT" "$FORCE_FULL" || true
        fi
    fi
done

echo "--- Script Execution Complete: $(date) ---"
