#!/bin/bash
# Cleanup old Btrfs snapshots locally and on backup destination.
# Run as root.
set -euo pipefail

# Number of latest snapshots to keep per subvolume
KEEP=3

# Subvolumes to clean snapshots for (use same list as your backup script)
SUBVOLUMES_TO_CLEAN=(
    "/"
    "/home"
    "/home/<user>/Pictures/latest"
)

# Backup destination where snapshots are stored (full path)
BACKUP_DEST="/run/media/<user>/BlackArmor/fedora2_snapshots"

# Simple check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d "$BACKUP_DEST" ]; then
    echo "ERROR: Backup destination $BACKUP_DEST does not exist or is not mounted."
    exit 1
fi

clean_snapshots_in_dir() {
    local SNAP_DIR=$1
    local SNAP_NAME=$2
    local KEEP_COUNT=$3

    # Ensure directory exists
    if [ ! -d "$SNAP_DIR" ]; then
        echo "INFO: Snapshot directory $SNAP_DIR does not exist. Skipping."
        return 0
    fi

    # Gather snapshots sorted (old -> new)
    mapfile -t snaps < <(find "$SNAP_DIR" -maxdepth 1 -mindepth 1 -type d -name "${SNAP_NAME}_*" | sort)

    local total=${#snaps[@]}
    if [ "$total" -le "$KEEP_COUNT" ]; then
        echo "INFO: $SNAP_DIR: $total snapshots found; keeping all (KEEP=${KEEP_COUNT})."
        return 0
    fi

    local to_delete_count=$((total - KEEP_COUNT))
    echo "INFO: $SNAP_DIR: $total snapshots found; deleting $to_delete_count oldest."

    for ((i=0; i<to_delete_count; i++)); do
        snap="${snaps[i]}"
        echo "Deleting local snapshot: $snap"
        if ! btrfs subvolume delete "$snap"; then
            echo "WARNING: Failed to delete local snapshot $snap. Continue with next."
        fi
    done
}

clean_snapshots_in_backup() {
    local SNAP_NAME=$1
    local KEEP_COUNT=$2

    # Snapshots stored directly under BACKUP_DEST with same names produced by backup script
    mapfile -t snaps < <(find "$BACKUP_DEST" -maxdepth 1 -mindepth 1 -type d -name "${SNAP_NAME}_*" | sort)

    local total=${#snaps[@]}
    if [ "$total" -le "$KEEP_COUNT" ]; then
        echo "INFO: $BACKUP_DEST: $total snapshots for ${SNAP_NAME} found; keeping all (KEEP=${KEEP_COUNT})."
        return 0
    fi

    local to_delete_count=$((total - KEEP_COUNT))
    echo "INFO: $BACKUP_DEST: $total snapshots for ${SNAP_NAME} found; deleting $to_delete_count oldest."

    for ((i=0; i<to_delete_count; i++)); do
        snap="${snaps[i]}"
        echo "Deleting backup snapshot: $snap"
        if ! btrfs subvolume delete "$snap"; then
            echo "WARNING: Failed to delete backup snapshot $snap. Continue with next."
        fi
    done
}

echo "=== btrfs snapshot cleanup started: $(date) ==="

for SOURCE_SUBVOL in "${SUBVOLUMES_TO_CLEAN[@]}"; do
    if [ "$SOURCE_SUBVOL" = "/" ]; then
        SNAP_DIR="/.snapshots"
        SNAP_NAME="root"
    else
        SNAP_DIR="${SOURCE_SUBVOL}/.snapshots"
        SNAP_NAME=$(basename "$SOURCE_SUBVOL")
    fi

    echo "Processing $SOURCE_SUBVOL -> snapshot name prefix: $SNAP_NAME"
    clean_snapshots_in_dir "$SNAP_DIR" "$SNAP_NAME" "$KEEP"
    clean_snapshots_in_backup "$SNAP_NAME" "$KEEP"
done

echo "=== cleanup complete: $(date) ==="

# Log script execution to syslog
logger -t btrfs_snapshot_cleanup_script "Snapshot cleanup script executed on $(date)"

exit 0
```// filepath: /home/stoflom/Workspace/btrfs_backup/cleanup_snapshots.sh