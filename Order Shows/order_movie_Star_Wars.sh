#!/usr/bin/env bash
# Star Wars Movie Extractor - Extracts movies and formats as "year *name*"


movie_url="https://www.space.com/star-wars-movies-in-order"
link_folder="/media/hermes/Paul/Media/Movies/Star Wars/"

include='order_movie.inc'
source_file=$(find "$HOME" -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

declare -A DEPCOMMANDS
DEPCOMMANDS+="lynx"

install_required_apps

check_url "$movie_url"

chron_ord=0
while read -r line; do
    if [[ "$line" == 'Get the Space.com Newsletter' ]]; then
        break
    fi
    if [ "$chron_ord" -lt 2 ]; then
        if [[ "$line" =~ Chronological\ order ]]; then
            ((chron_ord++))
        fi
        continue
    elif [ "$chron_ord" -eq 2 ]; then
        read -r line
        read -r line
        chron_ord=10
    elif [[ "$line" == '' ]]; then
        break
    fi
    line="${line#* }"
    if [[ "$line" =~ \*\^[0-9]$ ]]; then
        continue
    elif [[ "$line" =~ [Ss]eason ]]; then
        continue
    elif [[ "$line" =~ \([0-9]{4}-[0-9]{4}\) ]]; then
        continue
    elif [[ "$line" == 'Obi-Wan Kenobi (2022)' ]]; then
        continue
    elif [[ "$line" == 'Star Wars: The Acolyte (2024)' ]]; then
        continue
    elif [[ "$line" =~ \([0-9]{4}\) ]]; then
        # Extract year
        year="${line: -5}"
        year="${year#*(}"
        year="${year%)*}"
        # Extract title
        title="${line%%(*}"
        title="${title%" "}"  # Remove trailing space if needed
        movies+=( "$year|$title" )
#        printf '%s|%s\n' "$year" "$title"
    else
        echo "No valid date found"
    fi
done < <(lynx -dump -nolist "$movie_url" \
             | awk '/Star Wars movies in chronological order/{flag=1; next} /Star Wars movies in release order/{flag=0} flag')
# "${movies[@]}" - year|title
#echo "Movie count: ${#movies[@]}"
#printf '%s\n' "${movies[@]}"

make_folder "$link_folder"

create_links "$link_folder"
