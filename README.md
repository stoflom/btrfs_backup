# Bash Utilities

### System & Backup

#### `btrfs_backup.sh`

A script to take Btrfs snapshots of `/`, `/home`, and other specified subvolumes and send them incrementally to a mounted backup disk.

#### `cleanup_snapshots.sh`

A script to clean up old Btrfs snapshots from both local `.snapshots` directories and the backup destination. It keeps only a specified number of the latest snapshots for each subvolume.

### ⚠️ Disclaimer

These scripts are still under testing. While they are not intended to delete or corrupt data, it is crucial to **verify that your snapshots have been successfully copied to the backup media**. Use at your own risk.

---

## Usage

### Backup Script

```bash
sudo ./btrfs_backup.sh [-s|--send] [-h|--help]
```

Arguments:
*   `-s`, `--send`: Enables re-send and verification mode for the latest local snapshots. The script does not create new snapshots in this mode. Instead, it finds the latest local snapshot for each subvolume and checks if it exists and is complete on the backup destination. If missing or incomplete, it will be (re-)sent.
*   `-h`, `--help`: Display the help message and exit.

### Cleanup Script

```bash
sudo ./cleanup_snapshots.sh
```

This script will delete older snapshots and keep only the latest N snapshots (default: 3) for each configured subvolume, both locally and on the backup disk.

---

## ⚙️ Configuration

Before running the scripts, configure the subvolumes to be backed up and the backup destination. These settings are located at the top of the scripts.

**Example configuration from `btrfs_backup.sh` and `cleanup_snapshots.sh`:**

```bash
# Array of Btrfs subvolumes to back up/clean.
SUBVOLUMES_TO_BACKUP=(
    "/"
    "/home"
    "/home/<user>/Pictures/latest"
)

# The mount point of the backup disk.
BACKUP_MOUNT="/run/media/<user>/BlackArmor"
# NOTE: the backup disk must also be formatted with a btrfs filesystem.

# The Btrfs subvolume on the backup disk where snapshots will be sent/stored.
BACKUP_DEST="$BACKUP_MOUNT/fedora2_snapshots"

# Number of latest snapshots to keep (for cleanup script)
KEEP=3
```

---

## Initial Setup and Execution

1.  **Create Snapshot Directories**

    Ensure the Btrfs subvolumes where snapshots will be stored exist. The scripts are configured to store snapshots in directories like `/.snapshots` and `/home/.snapshots`. You must create these subvolume directories before running the scripts.

    ```bash
    # Example for root and home subvolumes
    sudo btrfs subvolume create /.snapshots
    sudo btrfs subvolume create /home/.snapshots
    ```

2.  **Run the Backup Script**

    Execute the script with root privileges:

    ```bash
    sudo ./btrfs_backup.sh
    ```

    To run in re-send and verification mode:

    ```bash
    sudo ./btrfs_backup.sh --send
    ```

3.  **Run the Cleanup Script**

    Execute the cleanup script to remove old snapshots:

    ```bash
    sudo ./cleanup_snapshots.sh
    ```

---

## Logging

Both scripts log important actions and completion status to syslog using the `logger` command. You can review logs with:

```bash
journalctl -t btrfs_backup_script
journalctl -t btrfs_snapshot_cleanup_script
```