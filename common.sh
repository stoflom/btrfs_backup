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
            echo "ERROR: Parent snapshot '$PARENT_NAME' exists on source but NOT on backup destination."
            echo "Use -s to sync the parent or -f for a full backup."
            return 1
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

# get_latest_common_parent SOURCE_SNAP_DIR BACKUP_DEST SNAP_NAME_PREFIX [TARGET_SNAP_PATH]
# Finds the most recent snapshot that exists on both source and destination
# and is complete on the destination.
# If TARGET_SNAP_PATH is provided, only snapshots older than it are considered.
get_latest_common_parent() {
    local SOURCE_DIR=$1
    local DEST_DIR=$2
    local PREFIX=$3
    local TARGET_PATH=${4:-""}

    local ALL_SOURCE_SNAPS
    ALL_SOURCE_SNAPS=$(find "$SOURCE_DIR" -maxdepth 1 -type d -name "${PREFIX}_[0-9]*" | sort -r)

    local FOUND_TARGET=false
    [ -z "$TARGET_PATH" ] && FOUND_TARGET=true

    while read -r SNAP; do
        [ -z "$SNAP" ] && continue
        
        if [ "$FOUND_TARGET" = false ]; then
            if [ "$SNAP" = "$TARGET_PATH" ]; then
                FOUND_TARGET=true
            fi
            continue
        fi

        local NAME=$(basename "$SNAP")
        if check_snapshot_complete "$DEST_DIR/$NAME"; then
            echo "$SNAP"
            return 0
        fi
    done <<< "$ALL_SOURCE_SNAPS"

    return 1
}

# show_current_config
show_current_config() {
    echo "Current Configuration:"
    echo "------------------------------------------------------"
    echo "SUBVOLUMES: (${SUBVOLUMES[*]})"
    echo "BACKUP_MOUNT: $BACKUP_MOUNT"
    echo "BACKUP_DEST: $BACKUP_DEST"
    echo "KEEP: $KEEP"
    echo "------------------------------------------------------"
}

# show_snapshot_info SUBVOLUMES_ARRAY BACKUP_DEST
show_snapshot_info() {
    local SUBVOLS=("${@:1:$#-1}")
    local DEST="${@: -1}"

    printf "%-30s | %-10s | %-15s\n" "Snapshot Name" "Source" "Backup (Type)"
    printf "%s\n" "----------------------------------------------------------------------------"

    for SOURCE_SUBVOL in "${SUBVOLS[@]}"; do
        get_snap_info "$SOURCE_SUBVOL"
        echo "Subvolume: $SOURCE_SUBVOL"

        # Get all unique snapshot names from both source and dest
        local all_snaps
        all_snaps=$( ( [ -d "$SNAP_DIR" ] && find "$SNAP_DIR" -maxdepth 1 -type d -name "${SNAP_NAME}_[0-9]*" -printf "%f\n" ; \
                      [ -d "$DEST" ] && find "$DEST" -maxdepth 1 -type d -name "${SNAP_NAME}_[0-9]*" -printf "%f\n" ) | sort -u)

        if [ -z "$all_snaps" ]; then
            echo "  No snapshots found."
            continue
        fi

        while read -r name; do
            [ -z "$name" ] && continue
            local src_status="MISSING"
            local dst_status="MISSING"
            local type_info=""

            if [ -d "$SNAP_DIR/$name" ]; then
                src_status="OK"
            fi

            if [ -d "$DEST/$name" ]; then
                local subvol_info
                subvol_info=$(btrfs subvolume show "$DEST/$name" 2>/dev/null)
                
                local check_status=0
                if [ -z "$subvol_info" ]; then
                    check_status=1
                else
                    local is_readonly=$(echo "$subvol_info" | grep -c 'Flags:.*readonly')
                    local has_received_uuid=$(echo "$subvol_info" | grep -c -E 'Received UUID:.*[a-f0-9]{8}-')
                    
                    if [ "$is_readonly" -eq 1 ] && [ "$has_received_uuid" -eq 1 ]; then
                        check_status=0
                    else
                        check_status=2
                    fi
                fi

                if [ $check_status -eq 0 ]; then
                    dst_status="OK"
                    # Check for Parent UUID to determine if it was incremental
                    local parent_uuid
                    parent_uuid=$(echo "$subvol_info" | grep "Parent UUID:" | awk '{print $3}')
                    if [ -n "$parent_uuid" ] && [ "$parent_uuid" != "-" ] && [[ ! "$parent_uuid" =~ ^0+$ ]]; then
                        type_info="(Inc)"
                    else
                        type_info="(Full)"
                    fi
                elif [ $check_status -eq 2 ]; then
                    dst_status="INCOMPLETE"
                else
                    dst_status="ERROR"
                fi
            fi

            printf "  %-28s | %-10s | %-10s %-5s\n" "$name" "$src_status" "$dst_status" "$type_info"
        done <<< "$all_snaps"
        echo ""
    done
}
