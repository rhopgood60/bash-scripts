#!/usr/bin/env bash

# ============================================================
#  METADATA LIBRARY
#  TMDB primary → OMDb fallback
#  Modular, reusable, explicit Bash
# ============================================================

tmdb_key="2efe35d421e3f55b58445468caf01ac8"
OMDB_KEY="19da871"

# ============================================================
# LOGGING HELPERS
# ============================================================
log_info()  { echo "ℹ️  $*"; }
log_warn()  { echo "⚠️  $*"; }
log_error() { echo "❌ $*"; }

# ============================================================
# SAFE JSON GET (avoids null)
# ============================================================
safe_json_get() {
    local file="$1"
    local key="$2"
    local val
    val="$(jq -r "$key // empty" "$file")"
    echo "$val"
}

# ============================================================
# NORMALIZE TITLE
# ============================================================
normalize_title() {
    local t="$1"
    echo "$t" | sed 's/\./ /g' | sed 's/_/ /g' | sed 's/  */ /g'
}

# ============================================================
# DATE PARSER (your existing logic)
# ============================================================
parse_date() {
    local VIDEODATE="$1"
    local day month year

    declare -A MONTHMAP=(
        [january]=01 [jan]=01
        [february]=02 [feb]=02
        [march]=03 [mar]=03
        [april]=04 [apr]=04
        [may]=05
        [june]=06 [jun]=06
        [july]=07 [jul]=07
        [august]=08 [aug]=08
        [september]=09 [sep]=09
        [october]=10 [oct]=10
        [november]=11 [nov]=11
        [december]=12 [dec]=12
    )

    VIDEODATE="${VIDEODATE,,}"

    if [[ "$VIDEODATE" =~ ^([0-9]{1,2})[[:space:]]+([a-z]{3})[[:space:]]+([0-9]{4})[[:space:]]*$ ]]; then
        day="${BASH_REMATCH[1]}"
        mon="${BASH_REMATCH[2]}"
        year="${BASH_REMATCH[3]}"
        month="${MONTHMAP[$mon]}"
        printf "%04d-%02d-%02d\n" "$year" "$((10#$month))" "$((10#$day))"
        return 0
    fi

    d1=$(echo "$VIDEODATE" | cut -f1 -d/ | cut -f1 -d\\ | cut -f1 -d- | cut -f1 -d" " | cut -f1 -d",")
    d2=$(echo "$VIDEODATE" | cut -f2 -d/ | cut -f2 -d\\ | cut -f2 -d- | cut -f2 -d" " | cut -f2 -d",")
    d3=$(echo "$VIDEODATE" | cut -f3 -d/ | cut -f3 -d\\ | cut -f3 -d- | cut -f3 -d" " | cut -f3 -d",")

    if [[ "$d1" =~ [a-z] ]]; then
        VIDEODATE="${VIDEODATE/$d1/${MONTHMAP[$d1]}}"
    elif [[ "$d2" =~ [a-z] ]]; then
        VIDEODATE="${VIDEODATE/$d2/${MONTHMAP[$d2]}}"
    elif [[ "$d3" =~ [a-z] ]]; then
        VIDEODATE="${VIDEODATE/$d3/${MONTHMAP[$d3]}}"
    fi

    if [[ "$VIDEODATE" =~ ^([0-9]{1,2})[[:space:]/\\,-]+([0-9]{1,2})[[:space:]/\\,-]+([0-9]{4})$ ]]; then
        printf "%04d-%02d-%02d\n" "${BASH_REMATCH[3]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$VIDEODATE" =~ ^([0-9]{1,2})[[:space:]/\\,-]+([0-9]{1,2})[[:space:]/\\,-]+([0-9]{4})$ ]]; then
        printf "%04d-%02d-%02d\n" "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$VIDEODATE" =~ ^([0-9]{4})[[:space:]/\\,-]+([0-9]{1,2})[[:space:]/\\,-]+([0-9]{1,2})$ ]]; then
        printf "%04d-%02d-%02d\n" "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[3]}))"

        return 0
    fi

    echo "Error: Date format not recognized for date: *$VIDEODATE*"
    return 1
}

# ============================================================
# TMDB LOOKUPS
# ============================================================

lookup_tmdb_series() {
    local title="$1"
    local year="$2"
    local encoded
    encoded=$(jq -rn --arg s "$title" '$s|@uri')

    local url
    if [[ -n "$year" ]]; then
        url="https://api.themoviedb.org/3/search/tv?api_key=$TMDB_KEY&query=$encoded&first_air_date_year=$year"
    else
        url="https://api.themoviedb.org/3/search/tv?api_key=$TMDB_KEY&query=$encoded"
    fi

    wget -q -O tmdb_series.json "$url"

    local id
    id=$(safe_json_get tmdb_series.json '.results[0].id')

    if [[ -z "$id" ]]; then
        log_warn "TMDB series lookup failed for: $title"
        return 1
    fi

    echo "$id"
}

lookup_tmdb_season() {
    local id="$1"
    local season="$2"

    wget -q -O tmdb_season.json \
        "https://api.themoviedb.org/3/tv/$id/season/$season?api_key=$TMDB_KEY"

    if [[ "$(safe_json_get tmdb_season.json '.id')" == "" ]]; then
        log_warn "TMDB season lookup failed"
        return 1
    fi

    return 0
}

lookup_tmdb_episode() {
    local id="$1"
    local season="$2"
    local episode="$3"

    wget -q -O tmdb_episode.json \
        "https://api.themoviedb.org/3/tv/$id/season/$season/episode/$episode?api_key=$TMDB_KEY"

    if [[ "$(safe_json_get tmdb_episode.json '.id')" == "" ]]; then
        log_warn "TMDB episode lookup failed"
        return 1
    fi

    return 0
}

lookup_tmdb_movie() {
    local title="$1"
    local year="$2"
    local encoded
    encoded=$(jq -rn --arg s "$title" '$s|@uri')

    local url
    if [[ -n "$year" ]]; then
        url="https://api.themoviedb.org/3/search/movie?api_key=$TMDB_KEY&query=$encoded&year=$year"
    else
        url="https://api.themoviedb.org/3/search/movie?api_key=$TMDB_KEY&query=$encoded"
    fi

    wget -q -O tmdb_movie.json "$url"

    local id
    id=$(safe_json_get tmdb_movie.json '.results[0].id')

    if [[ -z "$id" ]]; then
        log_warn "TMDB movie lookup failed for: $title"
        return 1
    fi

    echo "$id"
}

# ============================================================
# OMDb LOOKUPS (fallback)
# ============================================================

lookup_omdb_series() {
    local title="$1"
    local encoded
    encoded=$(jq -rn --arg s "$title" '$s|@uri')

    wget -q -O omdb_series.json \
        "https://www.omdbapi.com/?apikey=$OMDB_KEY&t=$encoded&type=series"

    if [[ "$(safe_json_get omdb_series.json '.Response')" != "True" ]]; then
        log_warn "OMDb series lookup failed for: $title"
        return 1
    fi

    echo "$(safe_json_get omdb_series.json '.imdbID')"
}

lookup_omdb_season() {
    local imdb="$1"
    local season="$2"

    wget -q -O omdb_season.json \
        "https://www.omdbapi.com/?apikey=$OMDB_KEY&i=$imdb&Season=$season"

    if [[ "$(safe_json_get omdb_season.json '.Response')" != "True" ]]; then
        log_warn "OMDb season lookup failed"
        return 1
    fi

    return 0
}

lookup_omdb_episode() {
    local imdb="$1"
    local season="$2"
    local episode="$3"

    wget -q -O omdb_episode.json \
        "https://www.omdbapi.com/?apikey=$OMDB_KEY&i=$imdb&Season=$season&Episode=$episode"

    if [[ "$(safe_json_get omdb_episode.json '.Response')" != "True" ]]; then
        log_warn "OMDb episode lookup failed"
        return 1
    fi

    return 0
}

lookup_omdb_movie() {
    local title="$1"
    local year="$2"
    local encoded
    encoded=$(jq -rn --arg s "$title" '$s|@uri')

    wget -q -O omdb_movie.json \
        "https://www.omdbapi.com/?apikey=$OMDB_KEY&t=$encoded&y=$year"

    if [[ "$(safe_json_get omdb_movie.json '.Response')" != "True" ]]; then
        log_warn "OMDb movie lookup failed"
        return 1
    fi

    return 0
}

# ============================================================
# MASTER LOOKUP FUNCTIONS
# ============================================================

metadata_lookup_series() {
    local title="$1"
    local year="$2"

    # TMDB primary
    local id
    id=$(lookup_tmdb_series "$title" "$year") && {
        echo "TMDB:$id"
        return 0
    }

    # OMDb fallback
    local imdb
    imdb=$(lookup_omdb_series "$title") && {
        echo "OMDB:$imdb"
        return 0
    }

    log_error "Series lookup failed for: $title"
    rm *{series,season,episode}.json
    return 1
}

metadata_lookup_movie() {
    local title="$1"
    local year="$2"

    local id
    id=$(lookup_tmdb_movie "$title" "$year") && {
        echo "TMDB:$id"
        return 0
    }

    lookup_omdb_movie "$title" "$year" && {
        echo "OMDB"
        return 0
    }

    log_error "Movie lookup failed for: $title"
    rm *movie.json
    return 1
}
