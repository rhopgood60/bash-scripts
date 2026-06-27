#!/usr/bin/env bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"

include='bash_functions'
source_file=$(find "$HOME" -type f -iname "$include" -print -quit 2>/dev/null)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

# Load metadata engine (contains TMDB_KEY + OMDB_KEY)
source "$SCRIPTPATH"/metadata_lib.sh

declare -A DEPCOMMANDS
DEPCOMMANDS["ffmpeg"]="ffmpeg"


show_usage() {
    cat << EOF
Usage: $0 -f <folder>

Required:
    -f, --folder          Folder for season of tv shows
    -h, --help            Show this help message

Examples:
    # Add/Update TV Show metadata for season
    $0 -f "/mnt/Paul/Media/TV Shows/Good Omens (2019-2026)/Good Omens - Season 01/"
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--folder)
            SEASON_FOLDER="$2"
            shift 2
            ;;
        -h|--help|*)
            show_usage
            exit 1
            ;;
    esac
done

install_required_apps

echo "Scanning: $SEASON_FOLDER"
find "$SEASON_FOLDER" -type f | sort |
    while IFS= read -r video; do
        video="${video//$'\r'/}"
        if [[ -z "$video" ]]; then
            continue
        fi
        if [[ "${video:0:1}" != '/' ]]; then
            video="/$video"
        fi
        if [[ ! -f "$video" ]]; then
            printf '❌ missing: [%s]\n\n' "$video"
            continue
        fi

        mime=$(file --mime-type -b -- "$video")
        if [[ $mime != video/* ]]; then
            continue
        fi

        printf 'RUNNING: [%s]\n' "$video"
        base=$(basename "$video")
        name="${base%.*}"

        ep=$(grep -oE \
            'S[0-9]{1,2}E[0-9]{1,2}|[0-9]{1,2}x[0-9]{1,2}' \
            <<< "$name")
        if [[ -z "$ep" ]]; then
            echo "NO EPISODE TAG: $name"
            continue
        fi

        meta=$(
            awk -v ep="$ep" '
                BEGIN { RS=""; IGNORECASE=1 }
                tolower($0) ~ tolower(ep) { print $0 }
            ' "$SCRIPTPATH/metadata_folder.ffmeta"
        )
        if [[ -n "$meta" ]]; then
            tmpfile="$SCRIPTPATH/metadata.ffmeta"
            {
                echo ";FFMETADATA1"
                echo "$meta"
            } > "$tmpfile"
            "$SCRIPTPATH/meta-ffmeta.sh" "$video"
        fi
    done
