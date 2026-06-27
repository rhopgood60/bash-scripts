#!/usr/bin/env bash
SCRIPTPATH=$(dirname "$(cd "${0%/*}" > /dev/null || exit; echo "$PWD"/"${0##*/}")")

include='bash_functions'
source_file=$(find "$HOME" -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

run_once

# Define the label of the USB drive
BACKUPDRIVE="Ringo"

SOURCE="$(findmnt -lo label,target | grep "$BACKUPDRIVE" | grep -v smb)"
SOURCE=${SOURCE#* }
SOURCE="${SOURCE#"${SOURCE%%[![:space:]]*}"}"
SOURCE="${SOURCE%"${SOURCE##*[![:space:]]}"}/Backup/$HOSTNAME/$USER"
echo "DESTINATION: *$SOURCE*"

# Check if the destination directory is mounted
if grep -qs "$SOURCE" /proc/mounts; then
    echo
    echo "Source directory '$SOURCE' is not mounted."
    echo
    exit 1
fi
# Ensure the destination directory exists
if [ ! -d "$SOURCE" ]; then
    echo
    echo "Source directory '$SOURCE' does not exist."
    echo
    exit 1
fi

declare -a RESTORE
n=1
for f in "$SOURCE"/* "$SOURCE"/.*; do
    filename=$(basename -- "$f")
    case $filename in
      '.' | '..') ;;
      *) RESTORE[n]="$f"
         echo "$f"
         ((n++));;
    esac
done

# --old-args               disable the modern arg-protection idiom
# --archive, -a            archive mode is -rlptgoD (no -A,-X,-U,-N,-H)
# --partial                keep partially transferred files
# --progress               show progress during transfer
# --info=progress2         option shows statistics based on the whole transfer, rather than individual file
# --update, -u             skip files that are newer on the receiver
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
              --update
              --ignore-errors
              --recursive
              --stats
              --relative
              --mkpath
              --group
              --owner)

time {
    rsync -"${RSYNCOPTIONS[@]}"  "$SOURCE" "$HOME"
}