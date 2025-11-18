# Bash Utilities

### System & Backup

#### `btrfs_backup.sh`

A script to take Btrfs snapshots of the `/`, `/home` and other specified subvolumes and send them incrementally to a backup disk.

### ⚠️ Disclaimer

This script is still under testing. While it is not intended to delete or corrupt data, it is crucial to **verify that your snapshots have been successfully copied to the backup media**. Use it at your own risk.

### Usage

```bash
./btrfs_backup.sh [-s|--send] [-h|--help]
```

Arguments:
*   `-s`, `--send`: Enables a re-send and verification mode for the latest local snapshots. When this flag is provided, the script does not create new snapshots. Instead, it finds the latest local snapshot for each subvolume and checks if it exists and is complete on the backup destination. If the snapshot is missing or incomplete, it will be (re-)sent.
*   `-h`, `--help`: Display the help message and exit.

### ⚙️ Configuration

Before running the script, you need to configure the subvolumes to be backed up and the backup destination. These settings are located at the top of the `btrfs_backup.sh` script.

```bash
# Example configuration from btrfs_backup.sh

# An array of Btrfs subvolumes to back up.
SUBVOLUMES_TO_BACKUP=(
	"/"
	"/home"
	"/home/<user>/Pictures/latest"
)

# The mount point of the backup disk.
BACKUP_MOUNT="/run/media/<user>/BlackArmor"

# The Btrfs subvolume on the backup disk where snapshots will be sent.
BACKUP_DEST="$BACKUP_MOUNT/fedora2_snapshots"
```

### Initial Setup and Execution

1.  **Create Snapshot Directories**

    Ensure the Btrfs subvolumes where snapshots will be stored exist. The script is configured to store snapshots in directories like `/snapshots` and `/home/snapshots`. You must create these subvolume directories before running the script.

    ```bash
    # Example for root and home subvolumes
    sudo btrfs subvolume create /snapshots
    sudo btrfs subvolume create /home/snapshots
    ```

2.  **Run the Script**

    Execute the script with root privileges:

    ```bash
    sudo ./btrfs_backup.sh
    ```

    To run in re-send and verification mode:

    ```bash
    sudo ./btrfs_backup.sh --send
    ```