declare -A title_alias=(
    ["Avengers"]="The Avengers"
    ["Avengers: Infinity War"]="Avengers Infinity War"
    ["Avengers: Endgame"]="Avengers Endgame"
    ["Ant-Man and the Wasp"]="Ant-Man and the Wasp"
    ["Black Panther: Wakanda Forever"]="Black Panther Wakanda Forever"
)

movie_folder="/media/hermes/Paul/Media/Movies/"
exclude='extended|richard|remastered|director|.srt'
movies=()
prev_year=''
separator='|'

# Simple normalizer: cut at first & or :, strip trailing roman numerals/Part N, trim spaces
normalize_title() {
    local t="$1"
    # Remove after & or :
    t="${t%%&*}"
    t="${t%%:*}"
    # Trim leading/trailing whitespace
    t="$(echo "$t" | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
    # Remove " (III)", "Part III", but only at end and only if preceded by space or "Part"
    t="$(echo "$t" | sed -E 's/[[:space:]]*\(?([Pp]art[[:space:]]+)?[IVXLCDM]+\)?$//')"
    # Remove year marker like " (2013 film)" or " (film)"
    t="$(echo "$t" | sed -E 's/ \([0-9]{4} film\)//; s/ \(film\)//')"
    # Collapse internal spaces
    t="$(echo "$t" | tr -s ' ')"
    # Final trim
    t="$(echo "$t" | xargs)"
    printf '%s' "$t"
}

find_movie_by_prefix() {
    local title="$1"
    local year="$2"

    # Split title into words
    IFS=' ' read -r -a words <<< "$title"

    local prefix=""
    local matches=()

    for ((i=0; i<${#words[@]}; i++)); do
        # Build up prefix word by word
        if [[ -z "$prefix" ]]; then
            prefix="${words[i]}"
        else
            prefix="$prefix ${words[i]}"
        fi

        # Try to find matching files
        mapfile -t found < <(
            find "$movie_folder" -type f -iname "${prefix} (${year}"'*' |
            grep -viE "$exclude"
        )

        if (( ${#found[@]} > 0 )); then
            matches=("${found[@]}")
            break
        fi
    done

    echo "${matches[@]}"
}

check_url() {
    local source_url="$1"
    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "$source_url")
    if [ "$HTTP_STATUS" -eq 404 ]; then
        echo "❌ Failed to fetch data. Check your URL: $source_url"
        exit 1
    fi
}

make_folder() {
    local source_url="$1"
    # Create link folder if it doesn't exist
    if [[ -d "$source_url" ]]; then
        rm -r "$source_url"
    fi
    mkdir -p "$source_url"
}

create_links() {
     n=1
     for entry in "${movies[@]}"; do
         year="${entry%%${separator}*}"
         title="${entry#*${separator}}"
         title="$(normalize_title "$title")"
         if [[ -n "${title_alias[$title]}" ]]; then
             title="${title_alias[$title]}"
         fi

#         mapfile -t matches < <(find "$movie_folder" -type f -iname "${title} (${year}"'*' | grep -viE "$exclude")
         mapfile -t matches < <(find "$movie_folder" -type f -iname "*${title}*(${year}-??-??)*" | grep -viE "$exclude")

         file=''
         case "${#matches[@]}" in
             0) file="$(find_movie_by_prefix "$title" "$year")"
               if [ -z "$file" ]; then
                    printf '❌ Movie not found for %s (%s):\n' "$title" "$year"
                    continue
                fi
                ;;
             1)  file="${matches[0]}"
                 ;;
             *) mapfile -t matches < <(find "$movie_folder" -type f -iname "*${title}*(${year}-??-??)*" | grep -viE "$exclude")
                case "${#matches[@]}" in
                0) printf '❌ Movie not found: %s (%s)\n' "$title" "$year" 
                   ;;
                1 ) file="${matches[0]}"
                    ;;
                * ) printf '⚠️ Multiple matches for %s (%s):\n' "$title" "$year"
                    ;;
                esac
                ;;
         esac
#        if [ -n "$file" ]; then
##            printf '%s\n' "$file"
#            ln -s "$file" "$link_folder/$(printf '%02d - %s' "$n" "$(basename "$file")")"
#            ((n++))
#        fi
        if [ -n "$file" ]; then
            base="$(basename "$file")"
            linkname="$(printf '%02d - %s' "$n" "$base")"
            ln -s "$file" "$link_folder/$linkname"

            # Check for matching subtitle
            srt="${file%.*}.srt"
            if [ -f "$srt" ]; then
                srtname="$(printf '%02d - %s' "$n" "$(basename "$srt")")"
                ln -s "$srt" "$link_folder/$srtname"
            fi

            ((n++))
        fi
     done
#    echo "$n"
}
