#!/bin/bash

ROOT="/mnt/Paul/Media/TV Shows/Babylon 5 (1994-1998)"
REL_DIR="$ROOT/Babylon 5 - Release"
CHR_DIR="$ROOT/Babylon 5 - Chronological"

rm -rf "$REL_DIR" "$CHR_DIR"
mkdir -p "$REL_DIR" "$CHR_DIR"

# Helper: add all video files from a folder
add_videos_from_folder() {
    folder="$1"
    out_array="$2"

    if [[ -d "$folder" ]]; then
        # Collect files into a temp list
        tmp_list=$(mktemp)

        find "$folder" -maxdepth 1 -type f -iname "*.mp4" -print > "$tmp_list"

        # Sort the list alphabetically (S01E01, S01E02, ...)
        while IFS= read -r f; do
            eval "$out_array+=(\"\$f\")"
        done < <(sort "$tmp_list")

        rm "$tmp_list"
    else
        echo "❌ Missing folder: $folder"
    fi
}


# Helper: add a single video file
add_video_file() {
    file="$1"
    out_array="$2"

    if [[ -f "$file" ]]; then
        eval "$out_array+=(\"\$file\")"
    else
        echo "❌ Missing file: $file"
    fi
}

# ------------------------------------------------------------
# RELEASE ORDER
# ------------------------------------------------------------
RELEASE_LIST=()

# 1. The Gathering
#add_video_file "$ROOT/Movies/Babylon 5 (1993-02-22) The Gathering.mp4" RELEASE_LIST
#add_video_file "$ROOT/Movies/Babylon 5 - The Gathering (1993)/Babylon 5 - The Gathering (1993).mp4" RELEASE_LIST

# 2. Season 1
add_videos_from_folder "$ROOT/Babylon 5 -  Season 1 - Signs and Portents" RELEASE_LIST

# 3. Season 2
add_videos_from_folder "$ROOT/Babylon 5 - Season 02 The Coming of Shadows" RELEASE_LIST

# 4. Season 3
add_videos_from_folder "$ROOT/Babylon 5 - Season 03 Point of No Return" RELEASE_LIST

# 5. Season 4
add_videos_from_folder "$ROOT/Babylon 5 - Season 04 No Surrender No Retreat" RELEASE_LIST

# 6. In the Beginning
add_video_file "$ROOT/Movies/Babylon 5 (1998-01-04) In The Beginning.mp4" RELEASE_LIST

# 7. Season 5
add_videos_from_folder "$ROOT/Babylon 5 - Season 05 The Wheel of Fire" RELEASE_LIST

# 8. Thirdspace
add_video_file "$ROOT/Movies/Babylon 5 (1998-07-19) Thirdspace.mp4" RELEASE_LIST

# 9. The River of Souls
add_video_file "$ROOT/Movies/Babylon 5 (1998-11-08) The River Of Souls.mp4" RELEASE_LIST

# 10. A Call to Arms
add_video_file "$ROOT/Movies/Babylon 5 (1999-01-03) A Call To Arms.mp4" RELEASE_LIST

# 11. Crusade
add_videos_from_folder "$ROOT/Crusade" RELEASE_LIST

# 12. Legend of the Rangers
add_video_file "$ROOT/Movies/Babylon 5 (2002-01-19) The Legend of the Rangers - To Live and Die in Starlight.mp4" RELEASE_LIST

# 13. The Lost Tales
add_video_file "$ROOT/Movies/Babylon 5 (2007-07-31) The Lost Tales.mp4" RELEASE_LIST


# Create symlinks
count=1
for vid in "${RELEASE_LIST[@]}"; do
    num=$(printf "%03d" "$count")
    base=$(basename "$vid")
    ln -s "$vid" "$REL_DIR/$num - $base"
    count=$((count + 1))
done

echo "✔ Release order video links created."


# ------------------------------------------------------------
# CHRONOLOGICAL ORDER
# ------------------------------------------------------------
CHRONO_LIST=()

# 1. In the Beginning
add_video_file "$ROOT/Movies/Babylon 5 (1998-01-04) In The Beginning.mp4" CHRONO_LIST

# 2. The Gathering
add_video_file "$ROOT/Movies/Babylon 5 (1993-02-22) The Gathering.mp4" CHRONO_LIST

# 3. Season 1
add_videos_from_folder "$ROOT/Babylon 5 -  Season 1 - Signs and Portents" CHRONO_LIST

# 4. Season 2
add_videos_from_folder "$ROOT/Babylon 5 - Season 02 The Coming of Shadows" CHRONO_LIST

# 5. Season 3
add_videos_from_folder "$ROOT/Babylon 5 - Season 03 Point of No Return" CHRONO_LIST

# 6. Season 4
add_videos_from_folder "$ROOT/Babylon 5 - Season 04 No Surrender No Retreat" CHRONO_LIST

# 7. Thirdspace
add_video_file "$ROOT/Movies/Babylon 5 (1998-07-19) Thirdspace.mp4" CHRONO_LIST

# 8. Season 5
add_videos_from_folder "$ROOT/Babylon 5 - Season 05 The Wheel of Fire" CHRONO_LIST

# 9. The River of Souls
add_video_file "$ROOT/Movies/Babylon 5 (1998-11-08) The River Of Souls.mp4" CHRONO_LIST

# 10. A Call to Arms
add_video_file "$ROOT/Movies/Babylon 5 (1999-01-03) A Call To Arms.mp4" CHRONO_LIST

# 11. Crusade
add_videos_from_folder "$ROOT/Crusade" CHRONO_LIST

# 12. Legend of the Rangers
add_video_file "$ROOT/Movies/Babylon 5 (2002-01-19) The Legend of the Rangers - To Live and Die in Starlight.mp4" CHRONO_LIST

# 13. The Lost Tales
add_video_file "$ROOT/Movies/Babylon 5 (2007-07-31) The Lost Tales.mp4" CHRONO_LIST


# Create symlinks
count=1
for vid in "${CHRONO_LIST[@]}"; do
    num=$(printf "%03d" "$count")
    base=$(basename "$vid")
    ln -s "$vid" "$CHR_DIR/$num - $base"
    count=$((count + 1))
done

echo "✔ Chronological order video links created."
