#! /bin/bash
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

FORCE_REENCODE=0
declare -A DEPCOMMANDS
DEPCOMMANDS["exiftool"]="exiftool"
DEPCOMMANDS["ffmpeg"]="ffmpeg"

cleanup_all_metadata() {
    local base="$1"

    # Remove ffmpeg metadata text files
    rm -f "$HOME/${base}"*.txt

    # Remove TMDB/OMDB JSON files
    rm -f "$HOME/${base}"*.json
}

# ------------------------------------------------------------
# TV METADATA
# ------------------------------------------------------------
TV_metadata () {

    SHOWFILE="$1"
    METAFILE="$HOME/$(basename "${SHOWFILE%.*}").txt"

    ffmpeg -y -loglevel error -i "$SHOWFILE" -f ffmetadata "$METAFILE"

    BASENAME="$(basename "$SHOWFILE")"

    if [[ "$BASENAME" =~ S([0-9]{2})E([0-9]{2}) ]]; then
        SEASON="${BASH_REMATCH[1]}"
        EPISODE="${BASH_REMATCH[2]}"
    else
        echo "❌ Could not parse season/episode from: $BASENAME"
        return 2
    fi

    ALBUM="${BASENAME% - S*}"
    SHOWDIR="$(basename "$(dirname "$SHOWFILE")")"
    SHOWYEAR="$(echo "$SHOWDIR" | grep -oE '[0-9]{4}' | head -n1)"

    NORMALIZED_ALBUM="$(normalize_title "$ALBUM")"

    # ------------------------------------------------------------
    # TMDB → OMDb fallback lookup
    # ------------------------------------------------------------
    lookup=$(metadata_lookup_series "$NORMALIZED_ALBUM" "$SHOWYEAR")

    if [[ "$lookup" =~ TMDB:(.*) ]]; then
        TMDB_ID="${BASH_REMATCH[1]}"
        SOURCE="TMDB"
        echo "Using TMDB ID: $TMDB_ID"

    elif [[ "$lookup" =~ OMDB:(.*) ]]; then
        IMDB_ID="${BASH_REMATCH[1]}"
        SOURCE="OMDB"
        echo "Using OMDb ID: $IMDB_ID"

    else
        echo "❌ No metadata source found for: $ALBUM"
        cleanup_all_metadata "$ALBUM"
        exit 1
    fi

    # ------------------------------------------------------------
    # FETCH METADATA
    # ------------------------------------------------------------
    if [[ "$SOURCE" == "TMDB" ]]; then

        SERIESJSON="$HOME/${ALBUM}.tmdb_series.json"
        wget -q -O "$SERIESJSON" \
          "https://api.themoviedb.org/3/tv/$TMDB_ID?api_key=$TMDB_KEY"

        SEASONJSON="$HOME/${ALBUM} - S${SEASON}.tmdb_season.json"
        wget -q -O "$SEASONJSON" \
          "https://api.themoviedb.org/3/tv/$TMDB_ID/season/$SEASON?api_key=$TMDB_KEY"

        EPISODEJSON="$HOME/${ALBUM} - S${SEASON}E${EPISODE}.tmdb_episode.json"
        wget -q -O "$EPISODEJSON" \
          "https://api.themoviedb.org/3/tv/$TMDB_ID/season/$SEASON/episode/$EPISODE?api_key=$TMDB_KEY"

        EP_EXT_JSON="$HOME/${ALBUM} - S${SEASON}E${EPISODE}.tmdb_external.json"
        wget -q -O "$EP_EXT_JSON" \
          "https://api.themoviedb.org/3/tv/$TMDB_ID/season/$SEASON/episode/$EPISODE/external_ids?api_key=$TMDB_KEY"

        TITLE="$(jq -r '.name' "$EPISODEJSON")"
        GENRE="$(jq -r '.genres | map(.name) | join(", ")' "$SERIESJSON")"
        RELEASED_RAW="$(jq -r '.air_date // ""' "$EPISODEJSON")"
        YEAR="$(echo "$RELEASED_RAW" | cut -d- -f1)"
        SYNOPSIS="$(jq -r '.overview // ""' "$EPISODEJSON")"
        ARTIST="$(jq -r '.guest_stars | map(.name) | join(", ")' "$EPISODEJSON")"
        ALBUMARTIST="$(jq -r '.crew[] | select(.job=="Director") | .name' "$EPISODEJSON" | paste -sd ", " -)"
        IMDBID="$(jq -r '.imdb_id // ""' "$EP_EXT_JSON")"

    else
        SERIESJSON="$HOME/${ALBUM}.omdb_series.json"
        wget -q -O "$SERIESJSON" \
          "https://www.omdbapi.com/?apikey=$OMDB_KEY&i=$IMDB_ID&plot=full"

        SEASONJSON="$HOME/${ALBUM} - S${SEASON}.omdb_season.json"
        wget -q -O "$SEASONJSON" \
          "https://www.omdbapi.com/?apikey=$OMDB_KEY&i=$IMDB_ID&Season=$SEASON"

        EPISODEJSON="$HOME/${ALBUM} - S${SEASON}E${EPISODE}.omdb_episode.json"
        wget -q -O "$EPISODEJSON" \
          "https://www.omdbapi.com/?apikey=$OMDB_KEY&i=$IMDB_ID&Season=$SEASON&Episode=$EPISODE"

        TITLE="$(jq -r '.Title' "$EPISODEJSON")"
        GENRE="$(jq -r '.Genre // ""' "$SERIESJSON")"
        RELEASED_RAW="$(jq -r '.Released // ""' "$EPISODEJSON")"
        YEAR="$(jq -r '.Year // ""' "$EPISODEJSON")"
        SYNOPSIS="$(jq -r '.Plot // ""' "$EPISODEJSON")"
        ARTIST="$(jq -r '.Actors // ""' "$EPISODEJSON")"
        ALBUMARTIST="$(jq -r '.Director // ""' "$EPISODEJSON")"
        IMDBID="$(jq -r '.imdbID // ""' "$EPISODEJSON")"
    fi

    RELEASED="$RELEASED_RAW"
    if [[ -n "$RELEASED" && "$RELEASED" != "null" ]]; then
        PARSED_DATE=$(parse_date "$RELEASED") || RELEASED=""
        RELEASED="$PARSED_DATE"
    fi

    # ------------------------------------------------------------
    # WRITE METADATA
    # ------------------------------------------------------------
    {
        echo ";FFMETADATA1"
        echo "title=$ALBUM - S${SEASON}E${EPISODE} - $TITLE"
        echo "genre=$GENRE"
        echo "season=$SEASON"
        echo "episode=$EPISODE"
        echo "artist=$ARTIST"
        echo "album=$ALBUM"
        echo "year=$YEAR"
        echo "album_artist=$ALBUMARTIST"
        echo "date=$RELEASED"
        echo "synopsis=$SYNOPSIS"
        echo "imdbID=$IMDBID"
    } > "$METAFILE"

    mkdir -p "$HOME/Videos/shows"
    OUTPUT="$HOME/Videos/shows/$(basename "${SHOWFILE%.*}.mp4")"
    # ------------------------------------------------------------
    # FIRST ATTEMPT: STREAM COPY (unless forced)
    # ------------------------------------------------------------
    if [[ "$FORCE_REENCODE" -eq 0 ]]; then
        if ffmpeg -nostats -loglevel error -y -nostdin \
                -i "$SHOWFILE" \
                -f ffmetadata -i "$METAFILE" \
                -map 0:v -map 0:a? \
                -map_metadata 1 \
                -c copy \
                -movflags +faststart \
                "$OUTPUT"; then

            cleanup_all_metadata "$ALBUM"
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
        -i "$SHOWFILE" \
        -f ffmetadata -i "$METAFILE" \
        -map 0:v -map 0:a? \
        -map_metadata 1 \
        -c:v libx264 -preset slow -crf 18 \
        -c:a aac -b:a 192k \
        -movflags +faststart \
        "$OUTPUT"

    cleanup_all_metadata "$ALBUM"
}

# ------------------------------------------------------------
# MOVIE METADATA (with full fallback)
# ------------------------------------------------------------
movie_metadata () {
    SHOWFILE="$1"
    BASENAME="$(basename "$SHOWFILE")"
    NAME="${BASENAME%.*}"

    DATE="$(echo "$NAME" | grep -oE '\([0-9]{4}-[0-9]{2}-[0-9]{2}\)' | tr -d '()')"
    TITLE="$(echo "$NAME" | sed -E 's/ *\([0-9]{4}-[0-9]{2}-[0-9]{2}\).*//')"
    SUBTITLE="$(echo "$NAME" | sed -E 's/.*\([0-9]{4}-[0-9]{2}-[0-9]{2}\) *//')"
    [[ "$SUBTITLE" == "$NAME" ]] && SUBTITLE=""

    NORMALIZED_TITLE="$(normalize_title "$TITLE $SUBTITLE")"

    lookup=$(metadata_lookup_movie "$NORMALIZED_TITLE" "${DATE:0:4}")

    if [[ "$lookup" =~ TMDB:(.*) ]]; then
        MOVIE_ID="${BASH_REMATCH[1]}"
        SOURCE="TMDB"
        echo "Using TMDB movie ID: $MOVIE_ID"

    elif [[ "$lookup" =~ OMDB ]]; then
        SOURCE="OMDB"
        echo "Using OMDb fallback for movie"

    else
        echo "❌ No metadata source found for movie: $TITLE"
        return 1
    fi

    if [[ "$SOURCE" == "TMDB" ]]; then

        MOVIE_DETAIL_JSON="$HOME/${TITLE// /_}.tmdb_movie_detail.json"
        wget -q -O "$MOVIE_DETAIL_JSON" \
          "https://api.themoviedb.org/3/movie/$MOVIE_ID?api_key=$TMDB_KEY&append_to_response=credits"

        MOVIE_EXT_JSON="$HOME/${TITLE// /_}.tmdb_movie_external.json"
        wget -q -O "$MOVIE_EXT_JSON" \
          "https://api.themoviedb.org/3/movie/$MOVIE_ID/external_ids?api_key=$TMDB_KEY"

        OMDB_TITLE="$(jq -r '.title' "$MOVIE_DETAIL_JSON")"
        OMDB_RELEASE="$(jq -r '.release_date // ""' "$MOVIE_DETAIL_JSON")"
        OMDB_YEAR="$(echo "$OMDB_RELEASE" | cut -d- -f1)"
        OMDB_GENRE="$(jq -r '.genres | map(.name) | join(", ")' "$MOVIE_DETAIL_JSON")"
        OMDB_DIRECTOR="$(jq -r '.credits.crew[] | select(.job=="Director") | .name' "$MOVIE_DETAIL_JSON" | paste -sd ", " -)"
        OMDB_ACTORS="$(jq -r '.credits.cast | map(.name) | join(", ")' "$MOVIE_DETAIL_JSON")"
        OMDB_PLOT="$(jq -r '.overview // ""' "$MOVIE_DETAIL_JSON")"
        OMDB_IMDBID="$(jq -r '.imdb_id // ""' "$MOVIE_EXT_JSON")"

    else

        JSON="$HOME/${TITLE// /_}.omdb_movie.json"
        wget -q -O "$JSON" \
          "https://www.omdbapi.com/?apikey=$OMDB_KEY&plot=full&t=$(jq -rn --arg s "$NORMALIZED_TITLE" '$s|@uri')&y=${DATE:0:4}"

        OMDB_TITLE="$(jq -r '.Title' "$JSON")"
        OMDB_YEAR="$(jq -r '.Year' "$JSON")"
        OMDB_RELEASE="$(jq -r '.Released // ""' "$JSON")"
        OMDB_GENRE="$(jq -r '.Genre' "$JSON")"
        OMDB_DIRECTOR="$(jq -r '.Director' "$JSON")"
        OMDB_ACTORS="$(jq -r '.Actors' "$JSON")"
        OMDB_PLOT="$(jq -r '.Plot' "$JSON")"
        OMDB_IMDBID="$(jq -r '.imdbID' "$JSON")"
    fi

    if [[ -n "$OMDB_RELEASE" && "$OMDB_RELEASE" != "N/A" ]]; then
        PARSED_DATE=$(parse_date "$OMDB_RELEASE")
    else
        PARSED_DATE=""
    fi

    METAFILE="$HOME/${TITLE// /_}.txt"
    {
        echo ";FFMETADATA1"
        echo "title=$OMDB_TITLE"
        echo "artist=$OMDB_ACTORS"
        echo "album_artist=$OMDB_DIRECTOR"
        echo "year=$OMDB_YEAR"
        echo "date=$PARSED_DATE"
        echo "genre=$OMDB_GENRE"
        echo "synopsis=$OMDB_PLOT"
        echo "imdbID=$OMDB_IMDBID"
    } > "$METAFILE"

    mkdir -p "$HOME/Videos/shows"
    OUTPUT="$HOME/Videos/shows/$(basename "${SHOWFILE%.*}.mp4")"
    # ------------------------------------------------------------
    # FIRST ATTEMPT: STREAM COPY (unless forced)
    # ------------------------------------------------------------
    if [[ "$FORCE_REENCODE" -eq 0 ]]; then
        if ffmpeg -nostats -loglevel error -y -nostdin \
                 -i "$SHOWFILE" \
                -f ffmetadata -i "$METAFILE" \
                -map 0:v -map 0:a? \
                -map_metadata 1 \
                -c copy \
                -movflags +faststart \
                "$OUTPUT"; then

            cleanup_all_metadata "${TITLE// /_}"
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
        -i "$SHOWFILE" \
        -f ffmetadata -i "$METAFILE" \
        -map 0:v -map 0:a? \
        -map_metadata 1 \
        -c:v libx264 -preset slow -crf 18 \
        -c:a aac -b:a 192k \
        -movflags +faststart \
        "$OUTPUT"

    cleanup_all_metadata "${TITLE// /_}"
}
# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
main() {
    VIDEO="$1"
    if [[ "$2" == "--force" ]]; then
        FORCE_REENCODE=1
    fi

    if [ -z "$VIDEO" ]; then
        echo "Usage: $0 <movie or tv show>"
        exit 1
    fi

    if [ ! -e "$VIDEO" ]; then
        echo "❌ File or folder not found: $VIDEO"
        exit 1
    fi

    if [ -f "$VIDEO" ]; then
        if file -i "$VIDEO" | grep -q video; then
            if [[ "$VIDEO" =~ S[0-9]{2}E[0-9]{2} ]]; then
                TV_metadata "$VIDEO"
            else
                movie_metadata "$VIDEO"
            fi
        fi
    fi

    if [ -d "$VIDEO" ]; then
        while IFS= read -r -d '' file; do
            if file -i "$file" | grep -q video; then
                if [[ "$file" =~ S[0-9]{2}E[0-9]{2} ]]; then
                    TV_metadata "$file"
                else
                    movie_metadata "$file"
                fi
            fi
        done < <(find "$VIDEO" -type f -print0)
    fi
}

TIMEFORMAT="\n⏱️ Elapsed: '%3lR  # $(basename "$0")"
time {
    install_required_apps
    main "$@"
}

exit
