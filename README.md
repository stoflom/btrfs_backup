# btrfs subvolume mounting script

This repository contains a script to mount btrfs subvolumes from an external btrfs drive into the `~/Pictures` tree (e.g. for darktable), and to unmount them again.

## Usage

```sh
./mount_btrfs_subvolumes.sh [-u|--unmount] [external_mountpoint] [mount_base]
```

The script must be run as root (e.g. via `sudo`), since it creates mount points and mounts filesystems.

### Arguments

| Argument | Description |
|---|---|
| `-u`, `--unmount` | Unmount the subvolumes instead of mounting them |
| `external_mountpoint` | The mount point of the external btrfs drive. Defaults to `EXTERNAL_MOUNT` in the script (dummy `/run/media/<user>/<drive_name>`, replace with your own) |
| `mount_base` | The directory under which the subvolume mount points are created. Defaults to `MOUNT_BASE` in the script (dummy `/home/<user>/Pictures`, replace with your own) |
| `-h`, `--help` | Print usage information |

Both positional arguments are optional and can be used in combination with the `-u` flag.

### Examples

```sh
# Mount all subvolumes from the drive into ~/Pictures
sudo ./mount_btrfs_subvolumes.sh /run/media/user/MyDrive /home/user/Pictures

# Unmount them again
sudo ./mount_btrfs_subvolumes.sh -u /run/media/user/MyDrive /home/user/Pictures
```

## How it works

- The script lists all subvolumes of the external drive with `btrfs subvolume list -R` and mounts each one under `<mount_base>/<subvolume_name>`, where `<subvolume_name>` is the last component of the subvolume path (e.g. `LIVE/PICTURES/PicFiles/Trees` becomes `<mount_base>/Trees`).
- The top-level subvolume (the drive root) is not mounted, only its sub-subvolumes.
- Mount points that are already mounted are left as-is and reported.
- With `-u|--unmount`, each subvolume mount point that is currently mounted is unmounted.

## Requirements

- A btrfs-formatted external drive, already mounted (e.g. automatically at `/run/media/<user>/<drive_name>` by your file manager)
- `btrfs-progs` installed (for `btrfs subvolume list`)
- The script must be run as root

## Alternative: fstab entries

If you prefer the kernel to mount the subvolumes automatically when the drive is connected, you can instead add entries to `/etc/fstab` using the filesystem UUID (from `blkid`) and a `subvol=` option (subvolume paths are listed with `sudo btrfs subvolume list -R <drive>`):

```
# Format: UUID of the filesystem  mount point  type  options  dump  pass
```
