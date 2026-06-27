#!/usr/bin/env bash
# DC Movies

movie_url="https://en.wikipedia.org/wiki/List_of_films_based_on_DC_Comics_publications"
link_folder="/media/hermes/Paul/Media/Movies/DC"

include='order_movie.inc'
source_file=$(find "$HOME" -path "$HOME/.docker/immich-app/postgres" -prune -o -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

check_url "$movie_url"

while read -r line; do
     if [[ $line =~ \<th\ colspan=\"4\"\>Upcoming\<\/th\> ]]; then
        break
    fi
    # Case 1: plain <td>YEAR</td>
    if [[ "$line" =~ ^[[:space:]]*\<td\>([0-9]{4})\</td\>$ ]]; then
        year="${BASH_REMATCH[1]}"
        if [[ "$prev_year" != "$year" ]]; then
            prev_year="$year"
            continue
        fi
    fi
    # Case 2: <td rowspan="...">YEAR</td>
    if [[ $line =~ \<td(\ rowspan=\"[0-9]*\")?\>([0-9]{4})\<\/td\> ]]; then
        year="${BASH_REMATCH[2]}"  # ✅ Use REMATCH[2] to get the year
        if [[ "$prev_year" != "$year" ]]; then
            prev_year="$year"
            continue
        fi
    fi
    if [[ $line =~ \<td\>\<i\>\<a\ href=\"[^\"]+\"\ title=\"([^\"]+)\" ]]; then
        title="${BASH_REMATCH[1]}"
        # Remove " (YYYY film)"
        title="${title// \([0-9][0-9][0-9][0-9] film\)/}"
        # Remove " (film)"
        title="${title// \(film\)/}"
        # Decode HTML entities (e.g., &amp;)
        title=$(echo "$title" | sed 's/&amp;/\&/g')
        movies+=( "$year$separator$title" )
#        echo "Movie: $year - $title"
    fi
done < <(curl -s "$movie_url" | hxnormalize -x | hxselect -s '\n' 'table.wikitable' | awk '/<th>Title<\/th>/,/<\/table>/')
# "${movies[@]}" - year|title
#echo "Movie count: ${#movies[@]}"
#printf '%s\n' "${movies[@]}"

make_folder "$link_folder"

create_links "$link_folder"
