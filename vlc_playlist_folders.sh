#!/usr/bin/env bash
if [[ -L "$0" ]]; then
    # Script was invoked via symlink → use invocation dir
    SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
else
    # Script is real file → resolve actual location
    if command -v realpath >/dev/null 2>&1; then
        SCRIPTPATH="$(dirname "$(realpath "$0")")"
    elif command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
        SCRIPTPATH="$(dirname "$(readlink -f "$0")")"
    else
        SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
    fi
fi

set -euo pipefail

playlist="${1:-/mnt/Paul/Media/vlc.xspf}"
[[ -r "$playlist" ]] || { echo "❌ Cannot read playlist: $playlist"; exit 1; }
sed -i 's/\r$//' "$playlist"

declare -A seen
declare -a folders_to_open
declare -a media_paths

# Collect media paths into array
while IFS= read -r path; do
    media_paths+=("$path")
done < <(grep -oP '(?<=<location>file://)[^<]+' "$playlist")

# Loop from last to first until folders repeat
for (( idx=${#media_paths[@]}-1 ; idx>=0 ; idx-- )); do
#    decoded=$(printf '%b' "${media_paths[idx]//%/\\x}")
    decoded=$(python3 -c "import sys, urllib.parse, html; print(html.unescape(urllib.parse.unquote(sys.argv[1])))" "${media_paths[idx]}")
    folder=$(dirname "$decoded")

    if [[ -n "${seen["$folder"]:-}" ]]; then
#        echo "🔁 Folder already seen: $folder — stopping"
        break
    fi

    seen["$folder"]=1
    folders_to_open+=("$folder")
#    echo "🗂️ Will open: $folder"
done

# Open folders
if which dolphin; then
    if ! which kstart5; then
        sudo apt install kde-cli-tools
    fi
    DISPLAY=:0 kstart5 dolphin "${folders_to_open[@]}" &
elif which nautilus; then
    setsid nautilus "${folders_to_open[@]}" >/dev/null 2>&1 &
elif which thunar; then
    DISPLAY=:0 thunar "${folders_to_open[@]}" &
else
    for folder in "${folders_to_open[@]}"; do
        echo "📂 Opening: $folder"
        xdg-open "$folder" &
    done
fi

echo "✅ Opened ${#folders_to_open[@]} unique media folders"
