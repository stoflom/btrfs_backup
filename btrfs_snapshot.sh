#!/bin/bash

set -euo pipefail

# --- Configuration ---
SUBVOLUMES_TO_SNAPSHOT=(
	"/home/<user>/Pictures/OtherPictures"
	"/home/<user>/Pictures/SourcePictures"
	"/home/<user>/Pictures/Trees"
)

# take_snapshot() function
# Creates a local read-only Btrfs snapshot.
#
# On success, it returns exit code 0.
# On failure, it returns a non-zero exit code.
#
# @param $1 SOURCE_SUBVOL   The source subvolume to snapshot (e.g., "/home").
# @param $2 NEW_SNAP_PATH   The full, absolute path for the new snapshot to be created.
take_snapshot() {
	local SOURCE_SUBVOL=$1
	local NEW_SNAP_PATH=$2

	echo "--- Creating read-only snapshot for '$SOURCE_SUBVOL' ---"
	echo "Snapshot path: $NEW_SNAP_PATH"

	if btrfs subvolume snapshot -r "$SOURCE_SUBVOL" "$NEW_SNAP_PATH"; then
		echo "SUCCESS: Snapshot created at $NEW_SNAP_PATH."
		return 0
	else
		echo "ERROR: Failed to create snapshot for '$SOURCE_SUBVOL' at '$NEW_SNAP_PATH'."
		return 1
	fi
}


# --- Main Execution ---

echo "--- btrfs_snapshot script execution Started: $(date) ---"

# Loop through the array and snapshot each subvolume
for SOURCE_SUBVOL in "${SUBVOLUMES_TO_SNAPSHOT[@]}"; do
	echo -e "======================================================"
	echo "Processing source subvolume: $SOURCE_SUBVOL"

	# --- Derive snapshot configuration from source subvolume ---
	if [ "$SOURCE_SUBVOL" = "/" ]; then
		# Special case for the root subvolume
		SNAP_DIR="/.snapshots"
		SNAP_NAME="root"
	else
		# For all other subvolumes
		SNAP_DIR="${SOURCE_SUBVOL}/.snapshots"
		SNAP_NAME=$(basename "$SOURCE_SUBVOL")
	fi

	# Ensure the snapshot directory exists
	mkdir -p "$SNAP_DIR"

	# Create new snapshot
	NEW_SNAP_NAME="${SNAP_NAME}_$(date +%Y%m%d%H%M%S)"
	NEW_SNAP_PATH="${SNAP_DIR}/${NEW_SNAP_NAME}"
	# Take the new snapshot
	take_snapshot "$SOURCE_SUBVOL" "$NEW_SNAP_PATH"; 
	
done

echo "--- Script Execution Complete: $(date) ---"

exit 0
