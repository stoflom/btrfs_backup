#!/bin/bash
set -e

# Must be run with root privileges

MOUNT_BASE="/home/stoflom/Pictures"

# This utility does not assume the filesystem is mounted and identifies the
#  filesystem by the UUID and not the device id (/dev/sdxy) since the device ids
#  are not persistent. 
# FIRST find the UUID of your Btrfs filesystem by running 
#  blkid  or  lsblk -f.
# Format:"NAME(mount point under $MOUNT_BASE):SUBVOL_PATH(Path on filesystem):UUID(UUID of filesystem)"
subvolumes=(
	"Trees:/LIVE/PICTURES/PicFiles/Trees:5e023779-af21-4873-8b24-594c9504b16a"
	"SourcePictures:/LIVE/PICTURES/PicFiles/SourcePictures:5e023779-af21-4873-8b24-594c9504b16a"
	"OtherPictures:/LIVE/PICTURES/PicFiles/OtherPictures:5e023779-af21-4873-8b24-594c9504b16a"
)

check_uuid() {
	local uuid="$1"
	if ! blkid -U "$uuid" >/dev/null 2>&1; then
		echo "ERROR: Btrfs UUID $uuid not found or not accessible"
		exit 1
	fi
}

mount_subvolume() {
	local name="$1"
	local subvol_path="$2"
	local uuid="$3"
	local mount_point="$MOUNT_BASE/$name"

	check_uuid "$uuid"

	if [ ! -d "$mount_point" ]; then
		mkdir -p "$mount_point"
		echo "Created mount point: $mount_point"
	fi

	if mountpoint -q "$mount_point"; then
		echo "$mount_point is already mounted"
		return 0
	fi

	if mount -t btrfs -o "subvol=$subvol_path,defaults" UUID="$uuid" "$mount_point"; then
		echo "Successfully mounted: $mount_point"
	else
		echo "ERROR: Failed to mount $mount_point"
		exit 1
	fi
}

main() {
	for subvol in "${subvolumes[@]}"; do
		IFS=':' read -r name path uuid <<< "$subvol"
		mount_subvolume "$name" "$path" "$uuid"
	done

	echo "All Btrfs subvolumes mounted successfully"
}

main
