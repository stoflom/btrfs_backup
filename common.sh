#!/bin/bash
# Shared functions for Btrfs backup and snapshot utilities

# get_snap_info SOURCE_SUBVOL
# Sets SNAP_DIR and SNAP_NAME based on the source subvolume.
get_snap_info() {
    local SOURCE_SUBVOL=$1
    if [ "$SOURCE_SUBVOL" = "/" ]; then
        SNAP_DIR="/.snapshots"
        SNAP_NAME="root"
    else
        SNAP_DIR="${SOURCE_SUBVOL}/.snapshots"
        SNAP_NAME=$(basename "$SOURCE_SUBVOL")
    fi
}

# take_snapshot SOURCE_SUBVOL NEW_SNAP_PATH
take_snapshot() {
    local SOURCE_SUBVOL=$1
    local NEW_SNAP_PATH=$2

    echo "--- Creating read-only snapshot for '$SOURCE_SUBVOL' ---"
    echo "Snapshot path: $NEW_SNAP_PATH"

    if btrfs subvolume snapshot -r "$SOURCE_SUBVOL" "$NEW_SNAP_PATH" > /dev/null; then
        echo "SUCCESS: Snapshot created at $NEW_SNAP_PATH."
        return 0
    else
        echo "ERROR: Failed to create snapshot for '$SOURCE_SUBVOL' at '$NEW_SNAP_PATH'." >&2
        return 1
    fi
}

# send_snapshot SNAPSHOT_TO_SEND BACKUP_DEST PARENT_SNAPSHOT FORCE_FULL_SEND
send_snapshot() {
    local SNAPSHOT_TO_SEND=$1
    local BACKUP_DEST=$2
    local PARENT_SNAPSHOT=$3
    local FORCE_FULL_SEND=${4:-false}
    local SNAP_NAME=$(basename "$SNAPSHOT_TO_SEND")

    echo "--- Sending snapshot '$SNAP_NAME' to '$BACKUP_DEST' ---"

    local USE_PARENT=""
    if [ "$FORCE_FULL_SEND" = "true" ]; then
        echo "INFO: Force full send requested. Ignoring parent."
    elif [ -n "$PARENT_SNAPSHOT" ]; then
        local PARENT_NAME=$(basename "$PARENT_SNAPSHOT")
        if [ ! -d "$PARENT_SNAPSHOT" ]; then
            echo "WARNING: Parent snapshot '$PARENT_SNAPSHOT' not found on source. Forcing a full send."
        elif [ ! -d "$BACKUP_DEST/$PARENT_NAME" ]; then
            echo "WARNING: Parent snapshot '$PARENT_NAME' not found on backup destination. Forcing a full send."
        else
            USE_PARENT="$PARENT_SNAPSHOT"
        fi
    fi

    local EXIT_CODE=0
    if [ -n "$USE_PARENT" ]; then
        echo "Performing INCREMENTAL send from parent: $USE_PARENT"
        btrfs send -p "$USE_PARENT" "$SNAPSHOT_TO_SEND" | btrfs receive "$BACKUP_DEST" || EXIT_CODE=$?
    else
        echo "Performing FULL send (no suitable parent found or forced)."
        btrfs send "$SNAPSHOT_TO_SEND" | btrfs receive "$BACKUP_DEST" || EXIT_CODE=$?
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        logger -t btrfs_backup_script -p local0.info "Snapshot ${SNAP_NAME} -> ${BACKUP_DEST} COMPLETED"
        echo "SUCCESS: Btrfs send/receive completed for ${SNAP_NAME}."
        return 0
    else
        logger -t btrfs_backup_script -p local0.error "Snapshot ${SNAP_NAME} -> ${BACKUP_DEST} FAILED"
        echo "ERROR: Btrfs send/receive failed for ${SNAP_NAME}." >&2
        return 1
    fi
}

# check_snapshot_complete SNAP_PATH
# Checks if a snapshot on the destination is complete (read-only and has received UUID).
check_snapshot_complete() {
    local SNAP_PATH=$1
    if [ ! -d "$SNAP_PATH" ]; then
        return 1
    fi

    local SUBVOL_INFO
    if ! SUBVOL_INFO=$(btrfs subvolume show "$SNAP_PATH" 2>/dev/null); then
        return 1
    fi

    local IS_READONLY
    IS_READONLY=$(echo "$SUBVOL_INFO" | grep -c 'Flags:.*readonly')
    
    local HAS_RECEIVED_UUID
    HAS_RECEIVED_UUID=$(echo "$SUBVOL_INFO" | grep -c -E 'Received UUID:.*[a-f0-9]{8}-')

    if [ "$IS_READONLY" -eq 1 ] && [ "$HAS_RECEIVED_UUID" -eq 1 ]; then
        return 0
    else
        return 2 # Exists but incomplete
    fi
}
