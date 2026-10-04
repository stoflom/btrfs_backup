#!/bin/bash
set -euo pipefail

# Must be run with root privileges.
#
# Mounts all subvolumes of an external btrfs drive into the
# ~/Pictures tree where darktable expects them. The top-level subvolume
# (the drive root) is NOT mounted, only its sub-subvolumes.
#
# Usage:
#   ./mount_btrfs_subvolumes.sh [-u|--unmount] [external_mountpoint|device] [mount_base]
#
# The first positional argument defaults to EXTERNAL_MOUNT; it can be a
# mount point of the drive or a block device (e.g. /dev/sda1). The
# mountpoint root defaults to MOUNT_BASE below. Use -u/--unmount to
# unmount the subvolumes instead of mounting them.

usage() {
	echo "Usage: $0 [-u|--unmount] [external_mountpoint|device] [mount_base]"
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

# Must be run as root (mounting, btrfs and blkid all need privileges)
if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: must be run as root (try: sudo $0 $*)" >&2
	exit 1
fi

# The first positional argument may also be a block device (e.g. /dev/sda1)
# instead of a mount point. 'btrfs subvolume list' needs a *path* (a mounted
# filesystem), while 'mount -o subvol=' needs a *block device*, so we track
# both: EXTERNAL_PATH for listing, EXTERNAL_DEVICE for mounting.
TMP_MOUNT=""
cleanup() {
	if [ -n "$TMP_MOUNT" ]; then
		umount "$TMP_MOUNT" 2>/dev/null || true
		rmdir "$TMP_MOUNT" 2>/dev/null || true
	fi
}
trap cleanup EXIT

if [ -b "$EXTERNAL_MOUNT" ]; then
	EXTERNAL_DEVICE="$EXTERNAL_MOUNT"

	# Validate that the device is a Btrfs filesystem (whole disks and
	# non-Btrfs partitions must be rejected up front)
	fs_type="$(blkid -o value -s TYPE "$EXTERNAL_DEVICE" 2>/dev/null || true)"
	if [ "$fs_type" != "btrfs" ]; then
		echo "ERROR: $EXTERNAL_DEVICE is not a Btrfs filesystem" >&2
		exit 1
	fi

	# Use the existing mount point if the device is already mounted;
	# otherwise mount it temporarily just to list the subvolumes.
	# NOTE: '|| true' is required - with 'set -o pipefail' a missing mount
	# point would make the pipeline fail and 'set -e' would abort silently.
	EXTERNAL_PATH="$(findmnt -n -o TARGET -S "$EXTERNAL_DEVICE" 2>/dev/null | head -n 1 || true)"
	if [ -z "$EXTERNAL_PATH" ]; then
		TMP_MOUNT="$(mktemp -d /mnt/btrfs-subvols-XXXXXX)"
		if ! mount "$EXTERNAL_DEVICE" "$TMP_MOUNT"; then
			echo "ERROR: could not temporarily mount $EXTERNAL_DEVICE at $TMP_MOUNT" >&2
			exit 1
		fi
		EXTERNAL_PATH="$TMP_MOUNT"
		echo "Temporarily mounted $EXTERNAL_DEVICE at $TMP_MOUNT to list subvolumes"
	else
		echo "Found existing mount point: $EXTERNAL_PATH"
	fi
else
	if ! mountpoint -q "$EXTERNAL_MOUNT"; then
		echo "ERROR: $EXTERNAL_MOUNT is neither a block device nor a mount point (is the drive connected?)" >&2
		exit 1
	fi

	EXTERNAL_PATH="$EXTERNAL_MOUNT"

	# Resolve the block device behind the mount point (mount with subvol=
	# needs a block device, not a directory)
	EXTERNAL_DEVICE="$(findmnt -n -o SOURCE --mountpoint "$EXTERNAL_MOUNT" || true)"
	if [ -z "$EXTERNAL_DEVICE" ]; then
		echo "ERROR: could not find the block device for $EXTERNAL_MOUNT" >&2
		exit 1
	fi
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
	local subvol_path list_output found=0

	# btrfs subvolume list -R prints lines like:
	#   ID 5   gen 1    top level 5 uuid <uuid> path
	#   ID 256 gen 4389 top level 5 uuid <uuid> path LIVE/PICTURES/PicFiles/Trees
	if ! list_output="$(btrfs subvolume list -R "$EXTERNAL_PATH" 2>&1)"; then
		echo "ERROR: failed to list subvolumes in $EXTERNAL_PATH:" >&2
		echo "$list_output" >&2
		exit 1
	fi

	while IFS= read -r line; do
		subvol_path="$(sed 's/^.* path //' <<< "$line")"

		# Skip the top-level subvolume (it has no path)
		[ -z "$subvol_path" ] && continue

		found=$((found + 1))
		if [ "$UNMOUNT" -eq 1 ]; then
			unmount_subvolume "$subvol_path"
		else
			mount_subvolume "$subvol_path"
		fi
	done <<< "$list_output"

	if [ "$found" -eq 0 ]; then
		echo "ERROR: no Btrfs subvolumes found in $EXTERNAL_PATH" >&2
		exit 1
	fi

	if [ "$UNMOUNT" -eq 1 ]; then
		echo "Done unmounting Btrfs subvolumes from $EXTERNAL_DEVICE"
	else
		echo "Done mounting Btrfs subvolumes from $EXTERNAL_DEVICE"
	fi
}

main
