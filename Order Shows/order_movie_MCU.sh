#!/usr/bin/env bash
# MCU Wars Movie Extractor - Extracts movies and formats as "year *name*"

movie_url="https://www.space.com/marvel-movies-in-order"
link_folder="/media/hermes/Paul/Media/Movies/MCU"

include='order_movie.inc'
source_file=$(find "$HOME" -path "$HOME/.docker/immich-app/postgres" -prune -o -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

check_url "$movie_url"

reading=false
title=""
year=""
while read -r line; do
    # Trim whitespace
    line="$(echo "$line" | awk '{$1=$1; print}')"

    # Start reading after separator
    if [[ "$line" == '__________________________________________________________________' ]]; then
        reading=true
        continue
    fi
    # Skip until we're in the right section
    if ! $reading; then
        continue
    fi

    # Match numbered title line
    if [[ "$line" =~ ^[0-9]+\.\ (.+)$ ]]; then
        title="${BASH_REMATCH[1]}"
        title="${title/\:/}"
        continue
    fi

    # Match release date line
    if [[ "$line" == *"Release date:"* ]]; then
        case "$title" in
        'Avengers Infinity War' ) year='2017'
                                  ;;
        'Ant-Man and the Wasp'  ) year='2017'
                                  ;;
        *                       ) year="${line: -4}"  # Last 4 characters
                                  ;;
        esac
#        echo "$year|$title"
        movies+=( "$year|$title" )
        title=""
        year=""
    fi
done < <(lynx -dump -nolist "$movie_url" \
            | awk '/Marvel movies in chronological order/{flag=1; next} /Marvel movies in release order/{flag=0} flag')
# "${movies[@]}" - year|title
#echo "Movie count: ${#movies[@]}"
#printf '%s\n' "${movies[@]}"

make_folder "$link_folder"

create_links "$link_folder"
