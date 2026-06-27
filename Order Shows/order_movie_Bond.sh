#!/usr/bin/env bash
# Bond Movie Extractor - Extracts movies and formats as "year *name*"

movie_url="https://en.wikipedia.org/wiki/List_of_James_Bond_films"
link_folder="/media/hermes/Paul/Media/Movies/007"

include='order_movie.inc'
source_file=$(find "$HOME" -path "$HOME/.docker/immich-app/postgres" -prune -o -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

check_url "$movie_url"

while IFS= read -r line; do
    input="$line"

    # Remove prefix
    raw="${input#toc-}"

    # Extract year using regex
    if [[ "$raw" =~ \([0-9]{4}(-[0-9]{2}){0,2}\) ]]; then
        year="${BASH_REMATCH[0]}"
        year="${year//[()]/}" # Remove parentheses
    else
        year="Unknown"
    fi

    # Extract title (remove year part and underscores)
    title="${raw%\(*}"
    title="${title//_/ }"
    title="${title//./ }"
    title="$(echo "$title" | sed 's/  */ /g' | sed 's/   ^ *//; s/ *$//')"

    # Output
    if [[ "$year" == '1983' ]]; then
        title="Never Say Never Again" # Non-Eon film
        year="1983"
    fi
    movies+=( "$year$separator$title" )
#    echo "Movie: $year - $title"
done < <(curl -s "$movie_url" | htmlq --attribute id 'ul#toc-Eon_films-sublist li')
# "${movies[@]}" - year|title
#echo "Movie count: ${#movies[@]}"
#printf '%s\n' "${movies[@]}"

make_folder "$link_folder"

create_links "$link_folder"
