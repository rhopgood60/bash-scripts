#!/bin/bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"
if [[ "$SCRIPTPATH" == "." ]]; then
    SCRIPTPATH="$PWD"
fi

# Function to display usage information
function usage() {
    echo "USAGE:"
    echo "    $0 video='<video file name>' title='<video title>' artist='<actors>' director='<director(s)>' release='<release date>' genre='<genre>' synopsis='<plot description>'"
    echo
    echo "All arguments are REQUIRED."
    exit 1
}

# Function to install AtomicParsley if not found
function install_atomicparsley() {
    echo "Checking for AtomicParsley..."
    if ! command -v AtomicParsley &>/dev/null; then
        echo "AtomicParsley not found. Attempting to install..."
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case $ID in
                ubuntu|debian)
                    sudo apt update && sudo apt install -y atomicparsley
                    ;;
                fedora|centos|rhel)
                    sudo dnf install -y atomicparsley
                    ;;
                arch)
                    sudo pacman -Syu atomicparsley --noconfirm
                    ;;
                *)
                    echo "Unsupported distribution. Please install AtomicParsley manually."
                    exit 1
                    ;;
            esac
        else
            echo "OS information not found. Please install AtomicParsley manually."
            exit 1
        fi
    else
        echo "AtomicParsley is already installed."
    fi
}

# Ensure AtomicParsley is available
install_atomicparsley

# Check if at least one argument is provided
if [[ $# -lt 1 ]]; then
    usage
fi

# Parse arguments into variables
for arg in "$@"; do
    case $arg in
        video=*) VIDEO_FILE="${arg#*=}" ;;
        title=*) TITLE="${arg#*=}" ;;
        artist=*) ARTIST="${arg#*=}" ;;
        director=*) DIRECTOR="${arg#*=}" ;;
        release=*) CONTENT_CREATE_DATE="${arg#*=}" ;;
        genre=*) GENRE="${arg#*=}" ;;
        synopsis=*) LONG_DESCRIPTION="${arg#*=}" ;;
        *) echo "Unknown argument: $arg"; usage ;;
    esac
done

# Validate required arguments
if [[ -z "$VIDEO_FILE" || -z "$TITLE" || -z "$ARTIST" || -z "$DIRECTOR" || -z "$CONTENT_CREATE_DATE" || -z "$GENRE" || -z "$LONG_DESCRIPTION" ]]; then
    echo "Error: All arguments are required."
    usage
fi

# Validate video file existence
if [[ ! -f "$VIDEO_FILE" ]]; then
    echo "Error: Video file '$VIDEO_FILE' not found."
    exit 1
fi

# Extract the file extension and base name
FILE_EXTENSION="${VIDEO_FILE##*.}"
BASE_NAME="${VIDEO_FILE%.*}"

# Convert file to .m4v if not already
if [[ "$FILE_EXTENSION" != "m4v" ]]; then
    OUTPUT_VIDEO_FILE="${BASE_NAME}.m4v"
    ffmpeg -i "$VIDEO_FILE" -c:v copy -c:a copy "$OUTPUT_VIDEO_FILE" -y
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to convert '$VIDEO_FILE' to .m4v."
        exit 1
    fi
else
    OUTPUT_VIDEO_FILE="$VIDEO_FILE"
fi

# Add metadata using AtomicParsley
AtomicParsley "$OUTPUT_VIDEO_FILE" --title "$TITLE" \
    --artist "$ARTIST" \
    --albumArtist "$DIRECTOR" \
    --year "${CONTENT_CREATE_DATE:0:4}" \
    --genre "$GENRE" \
    --description "$LONG_DESCRIPTION" \
    --overWrite

# Check if AtomicParsley succeeded
if [[ $? -eq 0 ]]; then
    echo "Metadata added successfully to '$OUTPUT_VIDEO_FILE'."
else
    echo "Failed to add metadata to '$OUTPUT_VIDEO_FILE'."
    exit 1
fi
