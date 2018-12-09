#!/bin/bash
/usr/local/sbin/restic_backup.sh --tag data --exclude .snapshots /mnt/nfs/data/
/usr/local/sbin/restic_backup.sh --tag owncloud --exclude .snapshots /mnt/nfs/owncloud

if [[ $(date +%u) -eq 6 ]]; then
	# perform weekly backups on saturday
	/usr/local/sbin/restic_backup.sh --tag Musik --exclude .snapshots /mnt/nfs/Musik
	/usr/local/sbin/restic_backup.sh --tag Fotos --exclude .snapshots --prune /mnt/nfs/Fotos
fi
