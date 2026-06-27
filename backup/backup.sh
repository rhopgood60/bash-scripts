#!/usr/bin/env bash
if [[ -L "$0" ]]; then
    # Script was invoked via symlink → use invocation dir
    SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
else
    # Script is real file → resolve actual location
    if command -v realpath >/dev/null 2>&1; then
        SCRIPTPATH="$(dirname "$(realpath "$0")")"
    elif command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
        SCRIPTPATH="$(dirname "$(readlink -f "$0")")"
    else
        SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
    fi
fi
###############################################################################################
#
# backup script
#
###############################################################################################
#
#include file

include='distro_info.sh'
source_file=$(find "$HOME" \
  \( -path "$HOME/.docker" \
     -o -path "$HOME/docker" \
     -o -path "$HOME/*/db" \
     -o -path "$HOME/*/data" \) -prune -o \
  -type f -iname "$include" -print -quit 2>/dev/null)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

###############################################################################################
# for debugging
# echo $LINUX_CODENAME
# echo $LINUX_RELEASE
# echo $LINUX_RELEASE_MAJOR
# echo $LINUX_RELEASE_MINOR
# echo $LINUX_DISTRIBUTION
# echo $DESKTOP_SESSION
# echo $ARCH

#case $(hostname) in
#  Herman  ) ;; # main
#  Lilly   ) ;; # secondary
#  Eddie   ) ;; # tertiary
#  Spot    ) ;; # virtual
#  Grandpa ) ;; # laptop
#  Marylyn ) ;; # netbook
#  Igor    ) ;; # phone
#  *       ) printf "\033[1;33mNot configured for this machine - %s\033[0m\n" "$(hostname)"
#            exit 1;;
#esac

###############################################################################################
#
#set variables

declare -a DEPCOMMANDS
DEPCOMMANDS+=("")

# yearly monthly weekly daily order MUST NOT change
BACKUP_TYPES=(
    "yearly"
    "monthly"
    "weekly"
    "daily"
)
# Set how many backup to keep variables
declare -A BACKUP_COUNT
BACKUP_COUNT["yearly"]=2
BACKUP_COUNT["monthly"]=13
BACKUP_COUNT["weekly"]=4
BACKUP_COUNT["daily"]=7
#echo ${BACKUP_COUNT[@]}

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
              --old-args
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
declare -a FOLDERLIST=(
    ".config/torbrowser"
    ".config/VirtualBox"
    ".config/vlc"
    ".d1x-rebirth"
    ".d2x-rebirth"
    ".local/share/torbrowser/tbb/x86_64"
    ".thunderbird"
    ".unison"
    ".vms"
    "Appdata"
    "Audio"
    "bin"
    "Documents"
    "Pictures"
    "Setup"
    "Music"
    "Videos"
    "VirtualBox VMs"
    "vlc"
    ".smbcredentials"
)
declare -a OMITLIST=(
    "crashes"
    "datareporting"
    "minidumps"
    "saved-telemetry-pings"
    "lock"
    "bookmarkbackups"
    ".parentlock"
    "Crash Reports"
    "Pending Pings"
    "systemextensionsdev"
    "sessionstore-backups"
    "DeletedCards"
    "DVDFab"
    "snap"
    "lost+found"
)

###############################################################################################
#
# functions

restore(){
# === Pseudo-code for restoring KVM/libvirt backups ===

# 1. Display available backup folders for selection
    echo "Available backup folders:"
    select folder in /path/to/backups/*; do
        echo "Selected backup: $folder"
        break
    done

# 2. Iterate through the key subfolders in the backup
    for f in "$folder"/*; do
        case "$(basename "$f")" in
            home)
                # Restore user-owned files (VM disks, XMLs)
                restore "$f" "$HOME/.vms/"
                ;;
            *)
                # Restore system-owned libvirt configs
                sudo restore "$f" "/etc/libvirt/$(basename "$f")/"
                ;;
        esac
    done

# 3. Fix ownership and permissions on VM disks
    sudo chown -R hermes:hermes "$HOME"
    sudo chown libvirt-qemu:kvm "$HOME"/.vms/*.qcow2
    sudo chmod 660              "$HOME"/.vms/*.qcow2

# 4. Re-define VMs from XML
    for xml in /etc/libvirt/qemu/*.xml; do
        sudo virsh define "$xml"
    done

# 5. Restore storage pools
    sudo virsh pool-define /etc/libvirt/storage/default.xml
    sudo virsh pool-define /etc/libvirt/storage/torrents.xml
    sudo virsh pool-autostart default
    sudo virsh pool-autostart torrents

# 6. Restore networks
    for netxml in /etc/libvirt/qemu/networks/*.xml; do
        sudo virsh net-define "$netxml"
        netname=$(basename "$netxml" .xml)
        sudo virsh net-autostart "$netname"
    done

# 7. Restore secrets if present
    if [[ -f /etc/libvirt/secrets/SECRET.xml ]]; then
        sudo virsh secret-define /etc/libvirt/secrets/SECRET.xml
    fi

# 8. Restore hooks
    sudo chmod +x /etc/libvirt/hooks/*

# 9. Restart libvirt to reload configs
    sudo systemctl restart libvirtd

# 10. Verify
    sudo virsh list --all
    sudo virsh pool-list --all
    sudo virsh net-list --all
} # restore

run_once_daily () {
    TODAY_RAW=$(date -u '+%Y-%m-%d')

    if [ -d "$DESTINATION/daily.0" ]; then
        DAILYDATE_RAW=$(date -u -r "$DESTINATION/daily.0" '+%Y-%m-%d')
        if [ "$TODAY_RAW" == "$DAILYDATE_RAW" ]; then
            return 1
        fi
    fi
    return 0
} # run_once_daily

get_folder_age_days() {
    local folder="$1"
    local now=$(date +%s)
    if [[ -d "$folder" ]]; then
        local birth=$(stat -c %W "$folder")
        if (( birth > 0 )); then
            echo $(( (now - birth) / 86400 ))
        else
            echo -1  # birth time not supported
        fi
    else
        echo -1
    fi
}

promote_folder() {
    local src="$1"
    local dst="$2"
    if [[ -d "$src" ]]; then
        echo "Promoting $src → $dst"
        rm -rf "$dst"
        mv "$src" "$dst"
    fi
} # promote_folder

rotate() {
    local period="$1"
        echo "Rotating $period"
        for ((i="BACKUP_COUNT[$period]"-1; i>=0; i--)); do
            if [[ -d "$DESTINATION/$period.$((i-1))" ]]; then
echo "$DESTINATION/$period.$((i-1))"
                mv "$DESTINATION/$period.$((i-1))" "$DESTINATION/$period.$i"
            fi
        done
} # rotate

rotate_folders() {
#if yearly.1 exists delete then 
#- if monthly.12 exists and is 1 year old move yearly.0 to yearly.1
#- move monthly.12 to yearly.0
#if monthly.0 is 4 weeks old rotate montly up 1
#- move weekly.3 to montly.0
#if weekly.0 is 7 days old rotate weekly up 1
#if daily.6 is 1 week old move to weekly.0
#rotate daily up 1

echo YEARLY
    TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # yearly rotation"
    time {
    # Yearly.1 cleanup
    if [[ -d "$DESTINATION/yearly.$((BACKUP_COUNT[yearly]-1))" ]]; then
        age=$(get_folder_age_days "$DESTINATION/yearly.$((BACKUP_COUNT[yearly]-1))")
        if (( age >= BACKUP_COUNT[daily] * BACKUP_COUNT[weekly] * BACKUP_COUNT[monthly] )); then
            echo "Deleting $DESTINATION/yearly.$((BACKUP_COUNT[yearly]-1))"
            rm -rff "$DESTINATION/yearly.$((BACKUP_COUNT[yearly]-1))"
        fi
    fi

    rotate_period=true
    for ((i=0; i<BACKUP_COUNT[yearly]; i++)); do
        folder="$DESTINATION/yearly.$i"
        if [[ -d "$folder" ]]; then
            age=$(get_folder_age_days "$folder")
            required_age=$(( (i + 1) * BACKUP_COUNT[daily]  * BACKUP_COUNT[weekly]  * BACKUP_COUNT[monthly] ))  # 364, 728
            echo "yearly.$i age = $age, required = $required_age"
            if (( age < required_age )); then
                rotate_period=false
                break
            fi
        fi
    done
    if $rotate_period; then
        rotate "yearly"
    fi
    } # time

echo MONTHLY
    TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # monthly rotation"
    time {
    # promote monthly.3 → yearly.0 if 364 days old
    # only if no weekly backups
    start=$(date +%s)
    if [[ -d "$DESTINATION/monthly.$((BACKUP_COUNT[monthly]-1))" ]]; then
        age=$(get_folder_age_days "$DESTINATION/monthly.$((BACKUP_COUNT[monthly]-1))")
        echo "age - $age"
        if (( age >= BACKUP_COUNT[daily] * BACKUP_COUNT[weekly] )); then
            echo "promote weekly"
            promote_folder "$DESTINATION/monthly.$((BACKUP_COUNT[monthly]-1))" "$DESTINATION/yearly.0"
        fi
    fi

    rotate_period=true
    declare -A ages
    while read -r name mtime; do
        now=$(date +%s)
        ages["$name"]=$(( (now - ${mtime%.*}) / 86400 ))
    done < <(find "$DESTINATION" -maxdepth 1 -type d -name 'monthly.*' -printf '%f %T@\n' 2>/dev/null)
    if [[ ${#ages[@]} -gt 0 ]]; then
        # Iterate over expected indices
        for ((i=0; i<BACKUP_COUNT[weekly]; i++)); do
            key="monthly.$i"
            if [[ -d "$DESTINATION/$key" ]]; then
                age=${ages[$key]}   # default 0 if not found
                required_age=$(( (i + 1) * BACKUP_COUNT[daily] ))  # 28, 56, 84, 112, 140, 168, 196, 224, 252, 280, 308, 336, 364
                echo "$key age = $age, required = $required_age"
                if (( age < required_age )); then
                    rotate_period=false
                fi
            fi
        done
    else
        rotate_period=false
    fi
    if $rotate_period; then
        rotate "monthly"
    fi
    unset ages
    } # time

echo WEEKLY
    TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # weekly rotation"
    time {
    # promote weekly.3 → monthly.0 if 28 days old
    # only if no weekly backups
    echo check for last weekly
    if [[ -d "$DESTINATION/weekly.$((BACKUP_COUNT[weekly]-1))" ]]; then
        age=$(get_folder_age_days "$DESTINATION/weekly.$((BACKUP_COUNT[weekly]-1))")
        echo "age - $age"
        if (( age >= BACKUP_COUNT[daily] )); then
            echo "promote weekly"
            promote_folder "$DESTINATION/weekly.$((BACKUP_COUNT[weekly]-1))" "$DESTINATION/monthly.0"
        fi
   fi

    rotate_period=true
    declare -A ages
    while read -r name mtime; do
        now=$(date +%s)
        ages["$name"]=$(( (now - ${mtime%.*}) / 86400 ))
    done < <(find "$DESTINATION" -maxdepth 1 -type d -name 'weekly.*' -printf '%f %T@\n' 2>/dev/null)
    if [[ ${#ages[@]} -gt 0 ]]; then
        # Iterate over expected indices
        for ((i=0; i<BACKUP_COUNT[weekly]; i++)); do
            key="weekly.$i"
            if [[ -d "$DESTINATION/$key" ]]; then
                age=${ages[$key]}   # default 0 if not found
                required_age=$(( (i + 1) * BACKUP_COUNT[daily] ))  # 7, 14, 21, 28
                echo "$key age = $age, required = $required_age"
                if (( age < required_age )); then
                    rotate_period=false
                fi
            fi
        done
    else
        rotate_period=false
    fi

    if $rotate_period; then
        rotate "weekly"
    fi
    } # time

echo DAILY
    TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # daily rotation"
    time {
    # promote daily.6 → weekly.0 if 7 days old
    # only if no weekly backups
    if [[ -d "$DESTINATION/daily.$((BACKUP_COUNT[daily]-1))" ]]; then
        age=$(get_folder_age_days "$DESTINATION/daily.$((BACKUP_COUNT[daily]-1))")
        if (( age >= "${BACKUP_COUNT[daily]}" )); then
            promote_folder "$DESTINATION/daily.$((BACKUP_COUNT[daily]-1))" "$DESTINATION/weekly.0"
        else
            rm -rf "$DESTINATION/daily.$((BACKUP_COUNT[daily]-1))"
        fi
    fi
    # Always rotate daily
    if [[ -d "$DESTINATION/daily.0" ]]; then
        rotate "daily"
    fi
    } # time
} # rotate_folders

###############################################################################################
#
# main
	
#install_app rclone 
startime

TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # backup - get desination"
time {
    install_required_apps

    if ! DESTINATION="$(get_drive 'backup')"; then
        echo_colour Red "ERROR $DESTINATION"
        exit 1
    fi
    DESTINATION="${DESTINATION}/Backup/$HOSTNAME/$USER"
    # Check and exit if directory does not exist
    if [ ! -d "$DESTINATION" ]; then
        mkdir -p "$DESTINATION"
    fi
    echo "DESTINATION: *$DESTINATION*"
}
#check if already executed
if ! run_once_daily; then
    echo_colour Green
    echo "🛑 Skipping backup — already done today."
    endtime
    elapsedtime "$STARTTIME" "$ENDTIME"
    echo_colour Yellow
    if ! read -t 10 -r -p "I am going to wait for 10 seconds only ... "; then
        echo    # prints a newline if read times out
    fi
    echo_colour NoColour
    exit
fi

# remove lock files
if [ -f "$HOME/.thunderbird/xzqru2dp.default-release/lock" ]; then
    sudo rm "$HOME/.thunderbird/xzqru2dp.default-release/lock"
fi
if [ -f "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/lock" ]; then
    sudo rm "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/lock"
fi
if [ -f "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/.config/ibus/bus" ]; then
    sudo rm "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/.config/ibus/bus"
fi

OMIT=()
for i in "${OMITLIST[@]}"; do
    unset OMITITEM
    mapfile -t OMITITEM < <(find . -type d -name "*$i*" 2>/dev/null)
    if [[ ${#OMITITEM[@]} -gt 0 ]]; then
        for o in "${OMITITEM[@]}"; do
            OMIT+=( "$o" )
        done
    fi
done
unset OMITITEM
unset OMITLIST
FOLDERS=()
for i in "${FOLDERLIST[@]}"; do
    if [[ -d "$HOME/$i" ]]; then
        FOLDERS+=( "$HOME/$i" )
    elif [[ -f "$HOME/$i" ]]; then
        FOLDERS+=( "$HOME/$i" )
    fi
done
unset FOLDERLIST
# Build exclude options as an array
EXCLUDE_OPTIONS=()
for path in "${OMIT[@]}"; do
    clean_path="${path#./}"
    EXCLUDE_OPTIONS+=( "--exclude=$clean_path" )
done
#EXCLUDE_STRING="$(IFS=" "; echo "${OMIT[*]}")"

echo "🟢 Proceeding with backup..."
# rotate backup directories
rotate_folders

#echo folders
#printf '\n%s' "${FOLDERS[@]}"
#echo options
#printf '\n%s' "${RCLONEOPTIONS[@]}"
#echo "exclude options"
#printf '\n%s' "${EXCLUDE_OPTIONS[@]}"
#RCLONE_CMD=(rclone copy "${FOLDERS[@]}" "$DESTINATION/daily.0" "${RCLONEOPTIONS[@]}" "${EXCLUDE_OPTIONS[@]}")
#echo "RCLONE CMD - ${RCLONE_CMD[@]}"

#DESTINATION="$(dirname $DESTINATION)"
RSYNC_CMD=("${RSYNCOPTIONS[@]}" "${EXCLUDE_OPTIONS[@]}" "${FOLDERS[@]}")
if [ -d "$DESTINATION/daily.1" ]; then
    RSYNC_CMD+=( "--link-dest=$DESTINATION/daily.1" )
fi
RSYNC_CMD+=( "$DESTINATION/daily.0/" )

# Show and run the command
TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # user backup"
time {
    echo "rsync DESTINATION: $DESTINATION"
    echo

    echo "🔍 Calculating total backup size..."
    TOTAL=$(rsync -a --dry-run --stats "${RSYNC_CMD[@]}")
    HUMAN=$(numfmt --to=iec --suffix=B "$TOTAL")
    echo "📦 Total size to process: $HUMAN"
    TOTAL=$(rsync -a --dry-run --stats \
                "${EXCLUDE_OPTIONS[@]}" \
                "${FOLDERS[@]}" \
                "$DESTINATION/daily.0/" \
            | awk '/Total file size:/ {gsub(/,/, "", $4); print $4}')
    HUMAN=$(numfmt --to=iec --suffix=B "$TOTAL")
    echo "📦 Total size to process: $HUMAN"

    rsync "${RSYNC_CMD[@]}"
    rc=$?
    echo "user rsync - $rc"
}

endtime
elapsedtime "$STARTTIME" "$ENDTIME"
