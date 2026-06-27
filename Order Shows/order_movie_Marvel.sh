#!/usr/bin/env bash
# All Marvel live Movies

movie_url="https://en.wikipedia.org/wiki/List_of_films_based_on_Marvel_Comics_publications"
link_folder="/media/hermes/Paul/Media/Movies/Marvel/"

include='order_movie.inc'
source_file=$(find "$HOME" -path "$HOME/.docker/immich-app/postgres" -prune -o -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

check_url "$movie_url"

prev_yr=''
while IFS= read -r line; do
    if [[ "$line" == '<tr style="background:#b0c4de;"><th colspan="5">Upcoming</th></tr>' ]]; then
        read -r line
        break
    fi
    if [[ "$line" == '<tr><th>Year</th><th>Title</th><th>Production studio(s)</th><th>Notes</th></tr>' ]]; then
        continue
    fi
    year=$(echo "$line" | grep -oP '<td(?: rowspan="\d+")?>\K[0-9]{4}(?=</td>)')
    title=$(echo "$line" | grep -oP '<i><a [^>]+ title="\K[^"]+')
    title=$(echo "$title" | sed -E 's/ \([0-9]{4}( film)?\)//; s/ \(film\)//')
    title="${title/:/}"  # Remove colon
 title="$(echo "$title" | xmlstarlet unesc)"
#    title="${title/&/}"  # Remove ampersand

    if [[ -z "$year" ]]; then
        year="$prev_yr"
    elif [[ "$prev_yr" != "$year" ]]; then
        prev_yr="$year"
    fi
    case "$title" in
    'Ant-Man and the Wasp'  ) year='2017'
                              ;;
    'Avengers Infinity War' ) year='2017'
                              ;;
    esac
    movies+=( "$year$separator$title" )
done < <(curl -s "$movie_url" | htmlq 'table.wikitable tbody tr' 2>/dev/null | awk '/Filming/{exit} {printf "%s", $0; if (/<\/tr>/) print ""}')
# "${movies[@]}" - year|title
#echo "Movie count: ${#movies[@]}"
#printf '%s\n' "${movies[@]}"

make_folder "$link_folder"

create_links "$link_folder"
