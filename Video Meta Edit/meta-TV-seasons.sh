#!/usr/bin/env bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"

# ============================================
# TV Show Season update metadata
# Usage: ./meta-TVShow.sh -f "/path/to/folder"
# ============================================

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
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--folder)
            SEASON_FOLDER="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

declare -a MISSED_VIDEO

TIMEFORMAT=$'\n⏱️ Elapsed: %3lR  (season metadata update)'
time {
    #echo "$SEASON_FOLDER"
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
            "$SCRIPTPATH/meta-edit.sh" "$video" < /dev/null
            if [[ $? -eq 1 ]]; then
                MISSED_VIDEO+=("❌ No metadata source found for: $(basename "$video")")
            fi
        done < <(find "$SEASON_FOLDER" -type f | sort)
}

printf "%s\n" "${MISSED_VIDEO[@]}"
