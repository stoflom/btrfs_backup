# Btrfs Backup & Snapshot Utilities

A collection of Bash scripts for automated Btrfs snapshot management, incremental backups to external drives, and mounting btrfs subvolumes from an external drive into the `~/Pictures` tree (e.g. for darktable).

## Key Features

- **Automated Snapshots**: Easily create read-only snapshots of multiple subvolumes.
- **Incremental Backups**: Send snapshots to a backup destination using `btrfs send/receive`.
- **Intelligent Cleanup**: Retain a configurable number of the latest snapshots both locally and on the backup destination.
- **Subvolume Mounting**: Utility to mount (and unmount) all subvolumes of an external btrfs drive into a chosen base directory.
- **Verification Mode**: Re-send missing or incomplete snapshots to ensure backup integrity.
- **System Logging**: All critical operations are logged to syslog for easy monitoring.

---

## 🛠️ Prerequisites

1.  **Btrfs Filesystem**: The source subvolumes and the backup destination must be on Btrfs.
2.  **Snapshot Directories**: Each subvolume you wish to snapshot must have a `.snapshots` subvolume at its root.
    
    *Example for `/` and `/home`:*
    ```bash
    sudo btrfs subvolume create /.snapshots
    sudo btrfs subvolume create /home/.snapshots
    ```
3.  **External Drive (for subvolume mounting)**: A btrfs-formatted external drive, already mounted (e.g. automatically at `/run/media/<user>/<drive_name>` by your file manager).
4.  **btrfs-progs**: Installed, for `btrfs subvolume list` and friends.

---

## ⚙️ Configuration

Settings are centralized in `config.sh`. This file must be configured before running the scripts.

| Variable | Description |
| :--- | :--- |
| `SUBVOLUMES` | Array of source subvolumes to backup (e.g., `"/"`, `"/home"`). |
| `BACKUP_MOUNT` | The mount point of your backup disk. |
| `BACKUP_DEST` | The specific subvolume/directory on the backup disk for storage. |
| `KEEP` | Number of latest snapshots to retain (default: 5). |

**Example `config.sh`:**
```bash
SUBVOLUMES=("/" "/home")
BACKUP_MOUNT="/run/media/user/BackupDrive"
BACKUP_DEST="$BACKUP_MOUNT/system_snapshots"
KEEP=5
```

---

## 💾 Installation

You can install the scripts using the provided `Makefile`. By default, they are installed to `/root/.local/bin`.

```bash
# Default installation (/root/.local/bin)
sudo make install

# Install to a custom location
sudo make install PREFIX=/usr/local
# OR
sudo make install BINDIR=/opt/bin
```

The `config.sh` file will be installed if it doesn't exist in the destination. If it already exists, it will be **retained** to preserve your settings.

To uninstall:
```bash
sudo make uninstall
```

---

## 🚀 Usage

All scripts must be run as **root**.

### 1. Snapshot and Backup (`btrfs_backup.sh`)
This is the primary script. It creates new snapshots and sends them to the backup destination.

```bash
sudo btrfs_backup.sh [OPTIONS]
```

- **No Arguments**: Creates new local snapshots and performs incremental sends to the backup destination.
- `-s, --send`: **Verification Mode**. Does not create new snapshots. Instead, it ensures the latest local snapshots are correctly transferred to the backup destination (useful for manual recovery or interrupted transfers).
- `-f, --full`: **Force Full Send**. Forces a full send-receive of the snapshots, ignoring parent snapshots.
- `-i, --info`: **Snapshot Info**. Displays a table showing the status (existence and completeness) of snapshots for each configured subvolume on both the source and the backup destination.
- `-c, --config`: **Current Config**. Displays the current configuration variables as defined in `config.sh`.
- `-h, --help`: Display help message.

### 2. Snapshot Only (`btrfs_snapshot.sh`)
Creates local snapshots without performing a backup.

```bash
sudo btrfs_snapshot.sh
```

### 3. Cleanup (`btrfs_snapshot_cleanup.sh`)
Removes old snapshots based on the `KEEP` variable in `config.sh`. By default, it cleans up both local `.snapshots` directories and the `BACKUP_DEST`.

```bash
sudo btrfs_snapshot_cleanup.sh [OPTIONS]
```

- **No Arguments**: Cleans up snapshots both locally and on the backup destination.
- `-k, --keep <num>`: **Override Keep Count**. Overrides the `KEEP` value from `config.sh` for this run.
- `-p, --preserve`: **Preserve Backup**. Only delete snapshots from the source subvolume and **NOT** from the backup destination.
- `-h, --help`: Display help message.

### 4. Mount Subvolumes (`mount_btrfs_subvolumes.sh`)
Mounts all subvolumes of an external btrfs drive into the `~/Pictures` tree (e.g. for darktable), and can unmount them again.

```bash
sudo ./mount_btrfs_subvolumes.sh [-u|--unmount] [external_mountpoint] [mount_base]
```

| Argument | Description |
|---|---|
| `-u`, `--unmount` | Unmount the subvolumes instead of mounting them |
| `external_mountpoint` | The mount point of the external btrfs drive. Defaults to `EXTERNAL_MOUNT` in the script (dummy `/run/media/<user>/<drive_name>`, replace with your own) |
| `mount_base` | The directory under which the subvolume mount points are created. Defaults to `MOUNT_BASE` in the script (dummy `/home/<user>/Pictures`, replace with your own) |
| `-h`, `--help` | Print usage information |

Both positional arguments are optional and can be used in combination with the `-u` flag.

**Examples:**
```bash
# Mount all subvolumes from the drive into ~/Pictures
sudo ./mount_btrfs_subvolumes.sh /run/media/user/MyDrive /home/user/Pictures

# Unmount them again
sudo ./mount_btrfs_subvolumes.sh -u /run/media/user/MyDrive /home/user/Pictures
```

**How it works:**

- The script lists all subvolumes of the external drive with `btrfs subvolume list -R` and mounts each one under `<mount_base>/<subvolume_name>`, where `<subvolume_name>` is the last component of the subvolume path (e.g. `LIVE/PICTURES/PicFiles/Trees` becomes `<mount_base>/Trees`).
- The top-level subvolume (the drive root) is not mounted, only its sub-subvolumes.
- Mount points that are already mounted are left as-is and reported.
- With `-u|--unmount`, each subvolume mount point that is currently mounted is unmounted.

### Alternative: fstab entries

If you prefer the kernel to mount the subvolumes automatically when the drive is connected, you can instead add entries to `/etc/fstab` using the filesystem UUID (from `blkid`) and a `subvol=` option (subvolume paths are listed with `sudo btrfs subvolume list -R <drive>`):

```
# Format: UUID of the filesystem  mount point  type  options  dump  pass
```

---

## 📝 Logging & Monitoring

The scripts use the `logger` command to record actions to the system log.

**View Backup Logs:**
```bash
journalctl -t btrfs_backup_script
```

**View Cleanup Logs:**
```bash
journalctl -t btrfs_snapshot_cleanup_script
```

---

## ⚠️ Disclaimer

These scripts are provided as-is. While designed for safety, always verify your backups manually. Use at your own risk.
