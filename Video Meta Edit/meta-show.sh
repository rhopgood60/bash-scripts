#!/usr/bin/env bash
#set -euo pipefail

FILE="${1:?usage: $0 <file>}"

# Ensure exiftool is installed
if ! command -v exiftool >/dev/null 2>&1; then
    sudo apt install -y libimage-exiftool-perl
fi

TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # Show Metadata"
time {
    # Extract all fields in one call
    TITLE=$(exiftool -s3 -Title "$FILE")
    ARTIST=$(exiftool -s3 -Artist "$FILE")
    ALBUMARTIST=$(exiftool -s3 -AlbumArtist "$FILE")
    CREATEDATE=$(exiftool -s3 -CreateDate "$FILE")
    GENRE=$(exiftool -s3 -Genre "$FILE")
    DESCRIPTION=$(exiftool -s3 -Description "$FILE")

    # Wrap DESCRIPTION to 66 columns and indent continuation lines
    WRAPPED_DESCRIPTION=$(echo "$DESCRIPTION" | fold -s -w 66 | sed '2,$s/^/              /')

    printf '%-12s: %s\n%-12s: %s\n%-12s: %s\n%-12s: %s\n%-12s: %s\n%-12s: %s\n' \
         "Title" "$TITLE" "Cast" "$ARTIST" "Director" "$ALBUMARTIST" "Release Date" "$CREATEDATE" "Genre" "$GENRE" "Synopsis" "$WRAPPED_DESCRIPTION"
}
