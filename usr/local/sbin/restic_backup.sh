#!/usr/bin/env bash
# Make backup my system with restic to Backblaze B2.
# This script is typically run by: /etc/systemd/system/restic-backup.{service,timer}

# Exit on failure, pipe failure
set -e -o pipefail

# Clean up lock if we are killed.
# If killed by systemd, like $(systemctl stop restic), then it kills the whole cgroup and all it's subprocesses.
# However if we kill this script ourselves, we need this trap that kills all subprocesses manually.
exit_hook() {
	echo "In exit_hook(), being killed" >&2
	jobs -p | xargs kill
	restic unlock
}
trap exit_hook INT TERM

# How many backups to keep (defaults).
RETENTION_DAYS=14
RETENTION_WEEKS=16
RETENTION_MONTHS=18
RETENTION_YEARS=3

# What to backup, and what to not
#BACKUP_EXCLUDES="--exclude-file /.backup_exclude --exclude-file /mnt/media/.backup_exclude --exclude-file /home/erikw/.backup_exclude"
BACKUP_TAG=systemd.timer

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -rd|--retain-daily)
    RETENTION_DAYS="$2"
    shift # past argument
    shift # past value
    ;;
    -rw|--retain-weekly)
    RETENTION_WEEKLY="$2"
    shift # past argument
    shift # past value
    ;;
    -rm|--retain-monthly)
    RETENTION_MONTHLY="$2"
    shift # past argument
    shift # past value
    ;;
    -ry|--retain-yearly)
    RETENTION_YEARLY="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--repository)
    RESTIC_REPOSITORY="$2"
    shift # past argument
    shift # past value
    ;;
    -x|--excludes)
    BACKUP_EXCLUDES="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--tag)
    BACKUP_TAG="$2"
    shift # past argument
    shift # past value
    ;;
    --prune)
    PRUNE=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -n $@ ]]; then
    BACKUP_PATHS="$@"
    echo "Starting backup for $BACKUP_PATHS"
fi

if [[ -z "$BACKUP_PATHS" ]]; then
  echo "parameters missing"
  echo "usage: restic_backup.sh -b --tag TAG --prune --retain-daily 14 --retain-weekly 16 --retain-monthly 18 --retain-yearly 2 BACKUP_PATH"
  exit 1
fi



# Set all environment variables like
# B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY etc.
source /etc/restic/b2_env.sh

# How many network connections to set up to B2. Default is 5.
B2_CONNECTIONS=50

# NOTE start all commands in background and wait for them to finish.
# Reason: bash ignores any signals while child process is executing and thus my trap exit hook is not triggered.
# However if put in subprocesses, wait(1) waits until the process finishes OR signal is received.
# Reference: https://unix.stackexchange.com/questions/146756/forward-sigterm-to-child-in-bash

# Remove locks from other stale processes to keep the automated backup running.
restic unlock &
wait $!

# Do the backup!
# See restic-backup(1) or http://restic.readthedocs.io/en/latest/040_backup.html
# --one-file-system makes sure we only backup exactly those mounted file systems specified in $BACKUP_PATHS, and thus not directories like /dev, /sys etc.
# --tag lets us reference these backups later when doing restic-forget.
restic backup \
	--verbose \
	--one-file-system \
	--tag $BACKUP_TAG \
	--option b2.connections=$B2_CONNECTIONS \
	$BACKUP_EXCLUDES \
	$BACKUP_PATHS &
wait $!

# Dereference old backups.
# See restic-forget(1) or http://restic.readthedocs.io/en/latest/060_forget.html
# --group-by only the tag and path, and not by hostname. This is because I create a B2 Bucket per host, and if this hostname accidentially change some time, there would now be multiple backup sets.
restic forget \
	--verbose \
	--tag $BACKUP_TAG \
	--group-by "paths,tags" \
	--keep-daily $RETENTION_DAYS \
	--keep-weekly $RETENTION_WEEKS \
	--keep-monthly $RETENTION_MONTHS \
	--keep-yearly $RETENTION_YEARS &
wait $!

# Remove old data not linked anymore.
# See restic-prune(1) or http://restic.readthedocs.io/en/latest/060_forget.html

if [[ -n "$PRUNE" ]]; then
	restic prune \
		--option b2.connections=$B2_CONNECTIONS \
		--verbose &
	wait $!
fi

# Check repository for errors.
# NOTE this takes much time (and data transfer from remote repo?), do this in a separate systemd.timer which is run less often.
#restic check &
#wait $!

echo "Backup & cleaning is done."
