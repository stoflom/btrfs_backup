# Configuration for Btrfs backup and snapshot utilities

# SUBVOLUMES: Array of Btrfs subvolumes to back up.
# The script will derive the snapshot directory and name prefix from these paths.
# The directory for snapshots will be created under each source subvolume root 
# (e.g., /home/.snapshots) and the unique snapshot name will be the basename 
# of the subvolume path + timestamp.
SUBVOLUMES=(
    "/"
    "/home"
    # "/home/stoflom/Pictures/latest"
)

# Backup Destination Mount Point
BACKUP_MOUNT="/run/media/stoflom/BlackArmor"

# Backup Destination Subvolume/Directory
# This is where the snapshots will be sent on the backup media.
BACKUP_DEST="$BACKUP_MOUNT/fedora2_snapshots"

# Number of latest snapshots to keep locally and on the backup destination.
KEEP=5
