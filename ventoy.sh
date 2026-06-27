#!/bin/bash

OUTDIR="$HOME/Downloads"
mkdir -p "$OUTDIR"
VENTOY_DIR="$HOME/ventoy"
# Direct download URL (no HTML redirect)

get_installed_ventoy_version() {
    local base="$HOME"
    local dir version

    # Find any folder matching ventoy-*-linux or ventoy-*
    dir=$(find "$base" -maxdepth 1 -type d -name "ventoy-*" | sort -V | tail -1)
    if [[ -z "$dir" ]]; then
        echo "none"
        return 1
    fi

    # Extract version from folder name
    version=$(basename "$dir" | sed -E 's/ventoy-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    echo "$version"
}

download_ventoy() {
    echo "Downloading:"
    echo "  $URL"

    curl -L "$URL" -o "$OUTDIR/ventoy-${LATEST}-linux.tar.gz"
    echo "Saved to: $OUTDIR/ventoy-${LATEST}-linux.tar.gz"
}

# Get current version - if exist
CURRENT="$(get_installed_ventoy_version)"
# Get latest version
LATEST=$(curl -s https://sourceforge.net/projects/ventoy/files/ \
    | grep -oP 'ventoy-[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V \
    | tail -1)
LATEST=${LATEST#*-}

if [[ "$CURRENT" != "$LATEST" || "$CURRENT" == "none" ]]; then
    URL="https://cfhcable.dl.sourceforge.net/project/ventoy/v${LATEST}/ventoy-${LATEST}-linux.tar.gz"
    download_ventoy
    # Extract
    mkdir -p "$VENTOY_DIR-$LATEST"
    tar -xvf "$OUTDIR/ventoy-${LATEST}-linux.tar.gz" -C "$HOME"
    rm -rf "$VENTOY_DIR-$CURRENT"
    rm "$OUTDIR/ventoy-${LATEST}-linux.tar.gz"
else
    LATEST="$CURRENT"
fi

echo "Latest Ventoy version: $LATEST"
"$VENTOY_DIR-$LATEST"/VentoyGUI.x86_64
