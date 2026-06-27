#!/usr/bin/env bash

OVERRIDE_FILE="${HOME}/.config/audiobooks/series-index.csv"

# ---------------------------------------------------------
# fetch_audible: search Audible and return JSON metadata
# ---------------------------------------------------------
fetch_audible() {
    local query="$1"
    local asin
    local json

    if [[ -z "$query" ]]; then
        echo "{}"
        return 1
    fi

    asin="$(curl -sG \
        --data-urlencode "keywords=${query}" \
        "https://api.audible.com/1.0/catalog/products" \
        | jq -r '.products[0].asin')"

    if [[ "$asin" == "null" || -z "$asin" ]]; then
        echo "{}"
        return 1
    fi

    json="$(curl -s \
        "https://api.audible.com/1.0/catalog/products/${asin}?response_groups=contributors,product_desc,media")"

    echo "$json"
}

# ---------------------------------------------------------
# fetch_openlibrary: search Open Library by title
# ---------------------------------------------------------
fetch_openlibrary() {
    local query="$1"
    local olid
    local json

    if [[ -z "$query" ]]; then
        echo "{}"
        return 1
    fi

    olid="$(curl -sG \
        --data-urlencode "title=${query}" \
        "https://openlibrary.org/search.json" \
        | jq -r '.docs[0].key')"

    if [[ "$olid" == "null" || -z "$olid" ]]; then
        echo "{}"
        return 1
    fi

    json="$(curl -s "https://openlibrary.org${olid}.json")"
    echo "$json"
}

# ---------------------------------------------------------
# fetch_googlebooks: search Google Books
# ---------------------------------------------------------
fetch_googlebooks() {
    local query="$1"
    local json

    if [[ -z "$query" ]]; then
        echo "{}"
        return 1
    fi

    json="$(curl -sG \
        --data-urlencode "q=${query}" \
        "https://www.googleapis.com/books/v1/volumes" \
        | jq '.items[0]')"

    if [[ "$json" == "null" ]]; then
        echo "{}"
        return 1
    fi

    echo "$json"
}

# ---------------------------------------------------------
# download_cover: pick best cover URL and save it
# ---------------------------------------------------------
download_cover() {
    local json="$1"
    local outfile="$2"
    local url

    if [[ -z "$json" || -z "$outfile" ]]; then
        echo "download_cover: missing arguments"
        return 1
    fi

    url="$(echo "$json" | jq -r '
        .cover // ""
    ')"

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "No cover URL available"
        return 1
    fi

    curl -s -o "$outfile" "$url"
#    echo "Saved cover: $outfile"
}

parse_audiobook_filename() {
    local file="$1"
    local base

    base="$(basename "$file" .m4b)"

    if [[ "$base" =~ ^(.+)\ \[([0-9]+)\]\ -\ (.+)\ -\ (.+)$ ]]; then
        printf '%s\n' \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}"

    elif [[ "$base" =~ ^(.+)\ -\ (.+)$ ]]; then
        printf '%s\n' \
            "" \
            "" \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}"
    fi
}

fix_author_name() {
    local name="$1"
    local first=""
    local last=""

    # Pattern: Lastname, Firstname
    if [[ "$name" =~ ^([^,]+),\ (.+)$ ]]; then
        last="${BASH_REMATCH[1]}"
        first="${BASH_REMATCH[2]}"
#echo "DEBUG: first: ${first} | last: ${last}" >&2
        echo "${first} ${last}"
    else
        # Already in First Last format
#echo "DEBUG: name: ${name}" >&2
        echo "$name"
    fi
}

# ---------------------------------------------------------
# resolve_series_index: override > filename > empty
# ---------------------------------------------------------

lookup_series_override() {
    local series="$1"
    local title="$2"
    local s t i

    [[ -f "$OVERRIDE_FILE" ]] || return 1

    while IFS='|' read -r s t i; do
        [[ "$s" == "$series" && "$t" == "$title" ]] || continue
        printf '%s\n' "$i"
        return 0
    done < "$OVERRIDE_FILE"

    return 1
}

resolve_series_index() {
    local file="$1"
    local series="$2"
    local title="$3"
    local base idx

    # 1) manual override
    if idx="$(lookup_series_override "$series" "$title")"; then
        printf '%s\n' "$idx"
        return 0
    fi

    # 2) filename index
    base="$(basename "$file")"
    if [[ "$base" =~ \[([0-9]+)\] ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    # 3) fallback
    printf '%s\n' ""
}

# ---------------------------------------------------------
# merge_metadata: combine Audible + OL + Google
# ---------------------------------------------------------
merge_metadata() {
    local query="$1"
    local audible_json
    local ol_json
    local google_json

    audible_json="$(fetch_audible "$query")"
    ol_json="$(fetch_openlibrary "$query")"
    google_json="$(fetch_googlebooks "$query")"

#    echo "=== AUDIBLE ===" >&2
#    jq . <<<"$audible_json" >&2
#    echo "=== OPENLIBRARY ===" >&2
#   jq . <<<"$ol_json" >&2
#    echo "=== GOOGLE ===" >&2
#    jq . <<<"$google_json" >&2

        jq -n \
        --argjson audible "$audible_json" \
        --argjson ol "$ol_json" \
        --argjson google "$google_json" \
        '
        {
            title:
                ($audible.product.title // $ol.title // $google.volumeInfo.title // ""),
            author:
                ($audible.product.authors[0].name // $ol.authors[0].name // $google.volumeInfo.authors[0] // ""),
            narrator:
                ($audible.product.narrators[0].name // ""),
            series:
                ($audible.product.series[0].title
                     // $audible.product.publication_name
                     // ""),
            series_index:
                 ($audible.product.series[0].sequence
                     // env.SERIES_INDEX
                     // ""),
            description:
                ($audible.product.merchandising_summary // $google.volumeInfo.description // ""),
            isbn:
                ($google.volumeInfo.industryIdentifiers[0].identifier // $ol.isbn_13[0] // ""),
            asin:
                ($audible.product.asin // ""),
            publisher:
                ($audible.product.publisher_name // $google.volumeInfo.publisher // ""),
            release_date:
                ($audible.product.release_date // $google.volumeInfo.publishedDate // ""),
            cover:
                ($audible.product.product_images["1200x1200"]
                     // $audible.product.product_images["500x500"]
                     // ("https://covers.openlibrary.org/b/id/" + ($ol.covers[0]|tostring) + "-L.jpg")
                     // $google.volumeInfo.imageLinks.thumbnail
                     // "")
        }
        '
}

# ---------------------------------------------------------
# update_metadata_with_tone: write merged metadata into file
# ---------------------------------------------------------
update_metadata_with_tone() {
    local file="$1"
    local json="$2"
    local cover="cover.jpg"

    # Extract fields from merged JSON
    local title author series series_index description publisher release_date narrator asin

    title="$(echo "$json" | jq -r '.title')"
    author="$(echo "$json" | jq -r '.author')"
    series="$(echo "$json" | jq -r '.series')"
    series_index="$(echo "$json" | jq -r '.series_index')"
    description="$(echo "$json" | jq -r '.description')"
    publisher="$(echo "$json" | jq -r '.publisher')"
    release_date="$(echo "$json" | jq -r '.release_date')"
    narrator="$(echo "$json" | jq -r '.narrator')"
    asin="$(echo "$json" | jq -r '.asin')"

    # Build tone command
    tone tag "$file" \
        --meta-title "$title" \
        --meta-artist "$author" \
        --meta-album "$series" \
        --meta-track-number "$series_index" \
        --meta-comment "$description" \
        --meta-publisher "$publisher" \
        --meta-publishing-date "$release_date" \
        --meta-narrator "$narrator" \
        --meta-additional-field "asin: $asin" \
        --meta-cover-file "$cover" | grep Update
}

# ---------------------------------------------------------
# main
# ---------------------------------------------------------
if [[ -z "$1" ]]; then
    echo "Usage: $0 \"Book Title\" [cover.jpg]"
    exit 1
fi

time {
    mapfile -t parsed < <(parse_audiobook_filename "$1")
    series="${parsed[0]}"
    index_from_filename="${parsed[1]}"
    series_index="$(resolve_series_index "$1" "$series" "$title")"
    export SERIES_INDEX="$series_index"
    title="${parsed[2]}"
    author="${parsed[3]}"
    author="$(fix_author_name "$author")"
    #printf 'series: %s\n Index: %s\n Title: %s\n author: %s\n' "$series" "$index" "$title" "$author"

    query="${title} ${author}"
    merged="$(merge_metadata "$query")"

    download_cover "$merged" "cover.jpg"

    update_metadata_with_tone "$1" "$merged"
}
