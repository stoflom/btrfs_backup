# Btrfs Backup & Snapshot Utilities

A collection of Bash scripts for automated Btrfs snapshot management and incremental backups to external drives.

## Key Features

- **Automated Snapshots**: Easily create read-only snapshots of multiple subvolumes.
- **Incremental Backups**: Send snapshots to a backup destination using `btrfs send/receive`.
- **Intelligent Cleanup**: Retain a configurable number of the latest snapshots both locally and on the backup destination.
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

## 🚀 Usage

All scripts must be run as **root**.

### 1. Snapshot and Backup (`btrfs_backup.sh`)
This is the primary script. It creates new snapshots and sends them to the backup destination.

```bash
sudo ./btrfs_backup.sh [OPTIONS]
```

- **No Arguments**: Creates new local snapshots and performs incremental sends to the backup destination.
- `-s, --send`: **Verification Mode**. Does not create new snapshots. Instead, it ensures the latest local snapshots are correctly transferred to the backup destination (useful for manual recovery or interrupted transfers).
- `-f, --full`: **Force Full Send**. Forces a full send-receive of the snapshots, ignoring parent snapshots.
- `-i, --info`: **Snapshot Info**. Displays a table showing the status (existence and completeness) of snapshots for each configured subvolume on both the source and the backup destination.
- `-h, --help`: Display help message.

### 2. Snapshot Only (`btrfs_snapshot.sh`)
Creates local snapshots without performing a backup.

```bash
sudo ./btrfs_snapshot.sh
```

### 3. Cleanup (`btrfs_snapshot_cleanup.sh`)
Removes old snapshots based on the `KEEP` variable in `config.sh`. It cleans up both local `.snapshots` directories and the `BACKUP_DEST`.

```bash
sudo ./btrfs_snapshot_cleanup.sh
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
