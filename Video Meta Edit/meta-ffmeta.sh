#!/bin/bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"

VIDEO="$1"
FORCE_REENCODE=0
if [[ "$2" == "--force" ]]; then
    FORCE_REENCODE=1
fi

SAVE="$(basename "${VIDEO%.*}.mp4")"
OUTPUT="$HOME/Videos/shows/$SAVE"

# ------------------------------------------------------------
# VALIDATE FFMETADATA FILE
# ------------------------------------------------------------
`="$SCRIPTPATH/metadata.ffmeta"

if [[ ! -f "$FFMETA" ]]; then
    echo "❌ metadata.ffmeta not found at: $FFMETA"
    exit 1
fi

# Must start with correct header
FIRST_LINE="$(head -n 1 "$FFMETA")"
if [[ "$FIRST_LINE" != ";FFMETADATA1" ]]; then
    echo "❌ metadata.ffmeta missing required ;FFMETADATA1 header"
    exit 1
fi

# Check for CRLF (Windows line endings)
if grep -q $'\r' "$FFMETA"; then
    echo "❌ metadata.ffmeta contains CRLF (Windows) line endings"
    exit 1
fi

# Check for BOM
if [[ "$(head -c 3 "$FFMETA")" == $'\xef\xbb\xbf' ]]; then
    echo "❌ metadata.ffmeta contains UTF‑8 BOM — remove it"
    exit 1
fi

# Validate each metadata line
LINE_NUM=0
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))

    # Skip header and blank lines
    if [[ "$LINE_NUM" -eq 1 ]]; then
        continue
    fi
    if [[ -z "$line" ]]; then
        continue
    fi

    # Must contain exactly one '='
    if [[ "$line" != *=* ]]; then
        echo "❌ Invalid metadata line (no '=') at line $LINE_NUM:"
        echo "   $line"
        exit 1
    fi

    KEY="${line%%=*}"
    VALUE="${line#*=}"

    # Key cannot be empty
    if [[ -z "$KEY" ]]; then
        echo "❌ Empty metadata key at line $LINE_NUM"
        exit 1
    fi

    # Key cannot contain spaces
    if [[ "$KEY" =~ [[:space:]] ]]; then
        echo "❌ Invalid key with spaces at line $LINE_NUM:"
        echo "   $KEY"
        exit 1
    fi

done < "$FFMETA"

echo "✔ metadata.ffmeta validated OK"

# ------------------------------------------------------------
# FIRST ATTEMPT: STREAM COPY (unless forced)
# ------------------------------------------------------------
if [[ "$FORCE_REENCODE" -eq 0 ]]; then

    if ffmpeg -nostats -loglevel error -y -nostdin \
            -i "$VIDEO" \
            -i "$SCRIPTPATH/metadata.ffmeta" \
            -map 0:v -map 0:a? \
            -map_metadata 1 \
            -c copy \
            -movflags +faststart \
            "$OUTPUT"; then

        echo "✔ Stream copy succeeded"
        exit 0

    else
        echo "⚠️  Stream copy failed — falling back to re‑encode"
    fi
else
    echo "⚠️  Force re‑encode enabled — skipping stream copy"
fi

# ------------------------------------------------------------
# SECOND ATTEMPT: SAFE H.264 + AAC RE‑ENCODE
# ------------------------------------------------------------
ffmpeg -nostats -loglevel error -y -nostdin \
    -i "$VIDEO" \
    -i "$SCRIPTPATH/metadata.ffmeta" \
    -map 0:v -map 0:a? \
    -map_metadata 1 \
    -c:v libx264 -preset slow -crf 18 \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    "$OUTPUT"
