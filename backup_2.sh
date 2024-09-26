#!/bin/bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"
if [[ "$SCRIPTPATH" == "." ]]; then
    SCRIPTPATH="$PWD"
fi
PARENT_NAME=$(basename "$0" .sh)
#echo "$SCRIPTPATH"

source "$SCRIPTPATH/bash_functions"
run_once

if [ -f "$HOME/.thunderbird/xzqru2dp.default-release/lock" ]; then
    sudo rm "$HOME/.thunderbird/xzqru2dp.default-release/lock"
fi
if [ -f "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/lock" ]; then
    sudo rm "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/lock"
fi
if [ -f "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/.config/ibus/bus" ]; then
    sudo rm "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/.config/ibus/bus"
fi

# yearly monthly weekly daily order MUST NOT change
BACKUP_TYPES=("yearly" "monthly" "weekly" "daily")
# Set how many backup to keep variables
declare -A BACKUP_COUNT
BACKUP_COUNT["yearly"]=2
BACKUP_COUNT["monthly"]=13
BACKUP_COUNT["weekly"]=4
BACKUP_COUNT["daily"]=7
#echo ${BACKUP_COUNT[@]}
BACKUPDRIVE="George"

DESTINATION="$(findmnt -lo label,target | grep "$BACKUPDRIVE" | grep -v smb)"
DESTINATION=${DESTINATION#* }
DESTINATION="${DESTINATION#"${DESTINATION%%[![:space:]]*}"}/Backup/$HOSTNAME/$USER"
# Check if the destination directory is mounted
if grep -qs "$DESTINATION" /proc/mounts; then
    echo
    echo "5 - Destination directory $DESTINATION is not mounted."
    echo
    exit 5
fi
# Ensure the destination directory exists
if [ ! -d "$DESTINATION" ]; then
    echo
    echo "Destination directory $DESTINATION does not exist."
    echo
    exit 6
fi 
echo "DESTINATION: *$DESTINATION*"

declare -a FOLDERS=(".config/torbrowser" ".config/VirtualBox" ".config/vlc" ".d1x-rebirth" ".d2x-rebirth" ".local/share/torbrowser/tbb/x86_64" ".thunderbird" ".unison" "AppData" "Audio" "bin" "Documents" "Pictures" "Setup" "Music" "Videos" "VirtualBox VMs" "vlc" ".smbcredentials")

declare -a OMIT=("crashes" "datareporting" "minidumps" "saved-telemetry-pings" "lock" "bookmarkbackups" ".parentlock" "Crash Reports" "Pending Pings" "systemextensionsdev" "sessionstore-backups" "DeletedCards" "DVDFab" "ViberDownloads" "lost+found")

EXCLUDE_STRING="$(IFS=" "; echo "${OMIT[*]}")"

# --old-args               disable the modern arg-protection idiom
# --archive, -a            archive mode is -rlptgoD (no -A,-X,-U,-N,-H)
# --partial                keep partially transferred files
# --progress               show progress during transfer
# -P                       equivalent to --partial --progress
# --info=progress2         option shows statistics based on the whole transfer, rather than individual file
# --update, -u             skip files that are newer on the receiver
# --human-readable -h
# --delete                 delete extraneous files from dest dirs
# --ignore-errors          delete even if there are I/O errors
# --recursive, -r          recurse into directories
# --stats                  give some file-transfer stats
# --quiet, -q              suppress non-error messages
# --relative, -R           use relative path names
# --group, -g              preserve group
# --owner, -o              preserve owner (super-user only)
# --exclude=PATTERN        exclude files matching PATTERN
# --link-dest=DIR          hardlink to files in DIR when unchanged
RSYNCOPTIONS=(--archive
              --partial
              --info=progress2
              --human-readable
              --update
              --delete
              --ignore-errors
              --recursive
              --stats
              --relative
              --group
              --mkpath
              --owner)

run_once_daily () {
    TODAY_RAW=$(date '+%Y-%m-%d')
    if [ -d "$DESTINATION/daily.0" ]; then
        DAILYDATE_RAW=$(date -r "$DESTINATION/daily.0" '+%Y-%m-%d')
        if [ "$TODAY_RAW" == "$DAILYDATE_RAW" ]; then
            echo .
            echo "Already successfully completed today"
            echo .
            exit
        fi
    else
        echo "$DESTINATION/daily.0 directory not found"
    fi
}

# Function to check and mount the backup drive
check_and_mount_backup_drive() {
    if ! findmnt -lo label,target | grep "$BACKUPDRIVE" | grep -v smb > /dev/null; then
        systemctl daemon-reload
        mount -a 
        if ! findmnt -lo label,target | grep "$BACKUPDRIVE" | grep -v smb > /dev/null; then
            echo "$BACKUPDRIVE NOT found"
            echo "Exiting $0"
            exit
        fi
    fi
}

move_backups () {
echo "$FUNCNAME"
    PERIOD="$1"
    echo ""
    echo "Rotating $PERIOD backups..."
    echo ""
        for ((i=BACKUP_COUNT["$PERIOD"] - 1; i>=0; i--)); do
            if [ -d "$DESTINATION/$PERIOD.$i" ]; then
                if [ "$i" -eq $(( BACKUP_COUNT["$PERIOD"] - 1 )) ]; then
                    rm -rf "$DESTINATION/$PERIOD.$i"
                else
                    mv "$DESTINATION/$PERIOD.$i" "$DESTINATION/$PERIOD.$((i+1))"
                fi
            fi
        done
}

shift_period () {
echo "$FUNCNAME"
    PERIOD="$1"
echo ""
echo "$DAYS_THRESHOLD"
echo ""
# weekly  - Check if the folder is at least 7 days ($(( BACKUP_COUNT["daily"] ))) old
# monthly - Check if the folder is at least 28 days ($(( BACKUP_COUNT["daily"] * BACKUP_COUNT["weekly"] ))) old
# yearly  - Check if the folder is at least 364 days ($(( BACKUP_COUNT["daily"] * BACKUP_COUNT["weekly"] * BACKUP_COUNT["monthly"] ))) old
        if [ ! -d "$DESTINATION/$PERIOD.0" ]; then
            mv "$BACKUP_FILE" "$DESTINATION/$PERIOD.0"
            touch "$DESTINATION/$PERIOD.0"
        fi
}

# Function to perform backup rotation
rotate_backup() {
echo "$FUNCNAME"
echo Rotate yearly backups
        DAYS_THRESHOLD=$(( BACKUP_COUNT["daily"] * BACKUP_COUNT["weekly"] * BACKUP_COUNT["monthly"] ))
        BACKUP_FILE="$DESTINATION/monthly.$(( BACKUP_COUNT["monthly"] - 1 ))"
if [[ -d "$DESTINATION/$(basename $BACKUP_FILE)" ]]; then
#        if find "$DESTINATION" -type d -name "$(basename $BACKUP_FILE)" -print -quit | grep -q .; then
            move_backups yearly
            shift_period yearly
        fi

echo Rotate monthly backups
    DAYS_THRESHOLD=$(( BACKUP_COUNT["daily"] * BACKUP_COUNT["weekly"] ))
    BACKUP_FILE="$DESTINATION/weekly.$(( BACKUP_COUNT["weekly"] - 1 ))"
if [[ -d "$DESTINATION/$(basename $BACKUP_FILE)" ]]; then
#        if find "$DESTINATION" -type d -name "$(basename $BACKUP_FILE)" -mtime +"$(( DAYS_THRESHOLD - 1 ))" -print -quit | grep -q .; then
            move_backups monthly
            shift_period monthly
        fi

echo Rotate weekly backups
    DAYS_THRESHOLD=$(( BACKUP_COUNT["daily"] ))
    BACKUP_FILE="$DESTINATION/daily.$(( BACKUP_COUNT["daily"] - 1 ))"
if [[ -d "$DESTINATION/$(basename $BACKUP_FILE)" ]]; then
#        if find "$DESTINATION" -type d -name "weekly.0" -mtime +"$(( DAYS_THRESHOLD - 1 ))" -print -quit | grep -q .; then
            move_backups weekly
            shift_period weekly
        fi

echo Rotate daily backups
    move_backups daily
}

# Check and mount backup drive
check_and_mount_backup_drive

#check if already executed
run_once_daily

#rotate backup directories
rotate_backup

# Set the linkdest option if daily.1 exists
if [ -d "$DESTINATION/daily.1" ]; then
    LINKDEST_OPTION="--link-dest=$DESTINATION/daily.1"
else
    LINKDEST_OPTION=""
fi

echo "rsync DESTINATION: $DESTINATION"
$(which rsync)                                \
     "${RSYNCOPTIONS[@]}"                     \
     "$EXCLUDE_STRING"                        \
     "${FOLDERS[@]}"                          \
     "$DESTINATION/daily.0"                   \
     "$LINKDEST_OPTION"
EXITCODE=$?
