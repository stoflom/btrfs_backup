#!/bin/bash
set -euo pipefail

# Must be run with root privileges.
#
# Mounts all subvolumes of an external btrfs drive into the
# ~/Pictures tree where darktable expects them. The top-level subvolume
# (the drive root) is NOT mounted, only its sub-subvolumes.
#
# Usage:
#   ./mount_btrfs_subvolumes.sh [-u|--unmount] [external_mountpoint] [mount_base]
#
# The external mountpoint defaults to EXTERNAL_MOUNT and the mountpoint
# root to MOUNT_BASE below; both can be overridden with command line
# arguments. Use -u/--unmount to unmount the subvolumes instead of
# mounting them.

usage() {
	echo "Usage: $0 [-u|--unmount] [external_mountpoint] [mount_base]"
}

# /home/<user> is a dummy directory - replace it with your own home directory
MOUNT_BASE="/home/<user>/Pictures"
# /run/media/<user>/<drive_name> is a dummy path - replace it with your own
# external drive mount point
EXTERNAL_MOUNT="/run/media/<user>/<drive_name>"
UNMOUNT=0

# Parse arguments: flags plus optional positional overrides
POSITIONAL=()
for arg in "$@"; do
	case "$arg" in
	-u|--unmount)
		UNMOUNT=1
		;;
	-h|--help)
		usage
		exit 0
		;;
	-*)
		echo "ERROR: unknown option: $arg" >&2
		usage >&2
		exit 1
		;;
	*)
		POSITIONAL+=("$arg")
		;;
	esac
done

if [ ${#POSITIONAL[@]} -ge 1 ]; then
	EXTERNAL_MOUNT="${POSITIONAL[0]}"
fi
if [ ${#POSITIONAL[@]} -ge 2 ]; then
	MOUNT_BASE="${POSITIONAL[1]}"
fi

if ! mountpoint -q "$EXTERNAL_MOUNT"; then
	echo "ERROR: $EXTERNAL_MOUNT is not a mount point (is the drive connected?)" >&2
	exit 1
fi

# Resolve the block device behind the mount point (mount with subvol= needs
# a block device, not a directory)
EXTERNAL_DEVICE="$(findmnt -n -o SOURCE --mountpoint "$EXTERNAL_MOUNT")"
if [ -z "$EXTERNAL_DEVICE" ]; then
	echo "ERROR: could not find the block device for $EXTERNAL_MOUNT" >&2
	exit 1
fi

mount_subvolume() {
	local subvol_path="$1"
	local name mount_point

	name="$(basename "$subvol_path")"
	mount_point="$MOUNT_BASE/$name"

	if [ ! -d "$mount_point" ]; then
		mkdir -p "$mount_point"
		echo "Created mount point: $mount_point"
	fi

	if mountpoint -q "$mount_point"; then
		echo "$mount_point is already mounted"
		return 0
	fi

	if mount -t btrfs -o "subvol=$subvol_path,defaults" "$EXTERNAL_DEVICE" "$mount_point"; then
		echo "Successfully mounted: $mount_point"
	else
		echo "ERROR: Failed to mount $mount_point"
		exit 1
	fi
}

unmount_subvolume() {
	local subvol_path="$1"
	local name mount_point

	name="$(basename "$subvol_path")"
	mount_point="$MOUNT_BASE/$name"

	if mountpoint -q "$mount_point"; then
		if umount "$mount_point"; then
			echo "Successfully unmounted: $mount_point"
		else
			echo "ERROR: Failed to unmount $mount_point"
			exit 1
		fi
	else
		echo "$mount_point is not mounted"
	fi
}

main() {
	local subvol_path

	# btrfs subvolume list -R prints lines like:
	#   ID 5   gen 1    top level 5 uuid <uuid> path
	#   ID 256 gen 4389 top level 5 uuid <uuid> path LIVE/PICTURES/PicFiles/Trees
	while IFS= read -r line; do
		subvol_path="$(sed 's/^.* path //' <<< "$line")"

		# Skip the top-level subvolume (it has no path)
		[ -z "$subvol_path" ] && continue

		if [ "$UNMOUNT" -eq 1 ]; then
			unmount_subvolume "$subvol_path"
		else
			mount_subvolume "$subvol_path"
		fi
	done < <(btrfs subvolume list -R "$EXTERNAL_MOUNT")

	if [ "$UNMOUNT" -eq 1 ]; then
		echo "Done unmounting Btrfs subvolumes from $EXTERNAL_MOUNT"
	else
		echo "Done mounting Btrfs subvolumes from $EXTERNAL_MOUNT"
	fi
}

main
