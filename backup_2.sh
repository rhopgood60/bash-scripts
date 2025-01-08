#!/bin/bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null || exit; echo "$PWD"/"${0##*/}")")"
if [[ "$SCRIPTPATH" == "." ]]; then
    SCRIPTPATH="$PWD"
fi
#*******************************************************************************
#
# bash function include
#
#*******************************************************************************

PSWD_HASH="9d095be844773adfc0f211b659361c57830f101024239cb93969b9266a0591cb"
declare -a DRIVES=("Ringo"
                   "Paul"
                   "John"
                   "George"
                   "Stuart"
                   "Pete")
declare -A ANSICOLOUR
ANSICOLOUR[Black]="\033[0;30m"
ANSICOLOUR[Red]="\033[0;31m"
ANSICOLOUR[Green]="\033[0;32m"
ANSICOLOUR[Orange]="\033[0;33m"
ANSICOLOUR[Blue]="\033[0;34m"
ANSICOLOUR[Purple]="\033[0;35m"
ANSICOLOUR[Cyan]="\033[0;36m"
ANSICOLOUR[LTGray]="\033[0;37m"
ANSICOLOUR[DKGray]="\033[1;30m"
ANSICOLOUR[LTRed]="\033[1;31m"
ANSICOLOUR[LTGreen]="\033[1;32m"
ANSICOLOUR[Yellow]="\033[1;33m"
ANSICOLOUR[LTBlue]="\033[1;34m"
ANSICOLOUR[LTPurple]="\033[1;35m"
ANSICOLOUR[LTCyan]="\033[1;36m"
ANSICOLOUR[White]="\033[1;37m"
ANSICOLOUR[NoColour]="\033[0m"

function echo_colour () { 
    local COLOUR="${ANSICOLOUR[$(echo -n "$1" | tr -d '[:space:]')]}"
    local TEXT="$2"
    if [[ -n "$3" ]]; then
        local COLOUR2="${ANSICOLOUR[$(echo -n "$3" | tr -d '[:space:]')]}"
    else
        local COLOUR2=""
    fi
    
    if [[ -z "$COLOUR" ]]; then
        echo "Error: Invalid or empty colour key: $COLOUR"
        return 1
    fi

    if [[ -z "$TEXT" ]]; then
        echo -e "${COLOUR}"
    else
        echo -e "${COLOUR}${TEXT}${COLOUR2}"
    fi
}  # echo_colour

function run_once() {
    script_name="$(basename "$0")"

    if pidof -o %PPID -x "$script_name" > /dev/null 2>&1; then
        log_info "$script_name is already running"
        exit 1
    fi
}  # run_once

function add_apt_key() {
    key_server="$1"
    apt_key="$2"
    apt_port="${3:-''}"

    # Check if the key_server URL is valid
    if [[ ! "$key_server" =~ ^hkp://.* ]]; then
        log_error "Invalid key URL: $key_server"
        return 1
    fi

    # Check if the key is already added
    if sudo keyctl search "$KEYRING_NAME" "$apt_key"; then
        log_info "Key $apt_key already exists in keyring $KEYRING_NAME"
        return 0
    fi

    # Add the key
    sudo apt-key adv --keyserver "$key_server""$apt_port" --recv-keys "$apt_key" || {
        log_error "Failed to add key: $key_server"
        return 1
    }

    # Verify the key's authenticity (optional)
    sudo gpg --check-keys --keyring /etc/apt/trusted.gpg.d/your_keyring.gpg "$apt_key" || {
        log_warning "Failed to verify key: $apt_key"
    }

    log_info "Key $apt_key added successfully"
    return 0
}  # add_apt_key

function install_repository() {
    repository_url="$1"

    # Check if the repository URL is valid
    if [[ ! "$repository_url" =~ ^"deb https?://."* ]]; then
        log_error "Invalid repository URL: $repository_url"
        return 1
    fi

    # Check if the repository is already added
    if grep -q "$repository_url" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        log_info "Repository $repository_url already present"
        return 0
    fi

    # Add the repository
    sudo apt-add-repository --yes --update "$repository_url" || {
        log_error "Failed to add repository: $repository_url"
        return 1
    }

    sudo apt update
    log_info "Repository $repository_url added successfully"
    return 0
}  # install_repository

function install_app() {
    executable_name="$1"

    if command -v "$executable_name" >/dev/null 2>&1; then
        log_info "$executable_name is already installed"
        return 0
    fi

    # Check if the package is installed with apt
    if dpkg-query -W -f='${Status}\n' "$executable_name" 2>/dev/null | grep -q "install ok installed"; then
        log_info "$executable_name is already installed with apt"
        return 0
    fi

    # Check if the package is installed with flatpak
    if flatpak list --app 2>&1 | grep -q "$executable_name"; then
        log_info "$executable_name is already installed with flatpak"
        return 0
    fi

    # Check if the package is installed with snap
    if snap list 2>&1 | grep -q "$executable_name"; then
        log_info "$executable_name is already installed with snap"
        return 0
    fi

    # Try to install using apt
    if sudo apt install -y "$executable_name"; then
        log_info "$executable_name installed using apt"
        return 0
    fi

    # Try to install using flatpak
    if sudo flatpak install -y flathub "$executable_name"; then
        log_info "$executable_name installed using flatpak"
        return 0
    fi

    # Try to install using snap
    if sudo snap install "$executable_name"; then
        log_info "$executable_name installed using snap"
        return 0
    fi

    log_error "Failed to install $executable_name"
    return 1
}  # install_app

function pushd_bf() {
    folder="$1"

    pushd "$folder" > /dev/null || {
        log_error "Failed to push directory: $folder"
        return 1
    }
}  # pushd_bf

function popd_bf() {
    popd > /dev/null || {
        log_error "Failed to pop directory"
        return 1
    }
}  # popd_bf

function save_IFS() {
    old_IFS="$IFS"
}  # save_IFS

function restore_IFS() {
    IFS="$old_IFS"
}  # restore_IFS

function ssh_open() {
    local MACHINE="$1"
    local TIMEOUT=5  # Adjust timeout as needed

    if ssh -o ConnectTimeout=$TIMEOUT "$MACHINE" 2>/dev/null; then
        log_info "SSH connection to $MACHINE successful"
    else
        log_error "Failed to connect to SSH: $MACHINE"
        return 1
    fi
}  # ssh_open

function starttime() {
    STARTTIME=$(date +%s) || {
        log_error "Failed to get start time"
        return 1
    }
}

function endtime() {
    ENDTIME=$(date +%s) || {
        log_error "Failed to get end time"
        return 1
    }
}

function elapsedtime() {
    SCRIPT="${1}"
# Check if STARTTIME and ENDTIME are set and valid numbers
    if [[ -z "$STARTTIME" || -z "$ENDTIME" ]]; then
        echo "Error: STARTTIME or ENDTIME not set."
        exit 1
    elif ! [[ "$STARTTIME" =~ ^[0-9]+$ ]] || ! [[ "$ENDTIME" =~ ^[0-9]+$ ]]; then
        echo "Error: STARTTIME or ENDTIME are not valid numbers."
        exit 1
    fi
    ELAPSEDTIME=$((ENDTIME - STARTTIME))
    echo
    printf '\n%s Elapsed time: %s\n' "$SCRIPT" "$(date -d@"${ELAPSEDTIME}" -u +%H:%M:%S.%3N)"
    echo
}

function strsub() {
    STR="$1"
    START="$2"
    LEN="$3"

    if [[ $START -lt 1 || $LEN -lt 0 ]]; then
        log_error "Invalid arguments for strsub: $STR, $START, $LEN"
        return 1
    fi

    echo "${STR:$START-1:$LEN}"
}  # strsub

function strright () {
# right_str "string" "length"
    local STR="$1"
    local LEN="$2"

    if [[ $LEN -lt 0 ]]; then
        log_error "Invalid arguments for strright: $STR, $LEN"
        return 1
    fi

    echo "${STR:(-$LEN)}"
}  # strright

function strleft () {
# left_str "string" "length"
    local STR="$1"
    local LEN="$2"

    if [[ $LEN -lt 0 ]]; then
        log_error "Invalid arguments for strleft: $STR, $LEN"
        return 1
    fi

    echo "${STR:0:$LEN}"
}  # strleft

function trimright () {
# right_str "string" "length"
    local STR="$1"
    local LEN="$2"

    if [[ $START -lt 1 || $LEN -lt 0 ]]; then
        log_error "Invalid arguments for trimright: $STR, $LEN"
        return 1
    fi

    echo "${STR:0:-$LEN}"
}  # trimright

function trimleft () {
# left_str "string" "length"
    local STR="$1"
    local LEN="$2"

    if [[ $LEN -lt 0 ]]; then
        log_error "Invalid arguments for trimleft: $STR, $LEN"
        return 1
    fi

    echo "${STR:$LEN:${#STR}}"
}  # trimleft

function log_info() {
    logger -t "$(basename $0): " "$1"
}  # log_info

function log_warning() {
    logger -t "$(basename $0): " "$1"
}  # log_warning

function log_error() {
    logger -t "$(basename $0): " "$1"
}  # log_error

function make_keyring() {
    KEYRING_NAME="$(hostname)_keyring"
    KEY_NAME="$(hostname)_pswd"
    KEYRING_NAME="pi_keyring"
    KEY_NAME="pi_pswd"

    if sudo keyctl search "$KEYRING_NAME" "$KEY_NAME"; then
        log_info "Keyring $KEYRING_NAME already exists."
    else
        sudo keyctl add keyring "$KEYRING_NAME" || {
            log_error "Failed to create keyring: $KEYRING_NAME"
            exit 1
        }
        sudo keyctl add session keyring "$KEYRING_NAME" || {
            log_error "Failed to add keyring to session: $KEYRING_NAME"
            exit 1
        }
        sudo keyctl insert "$KEYRING_NAME" "$KEY_NAME" || {
            log_error "Failed to store password in keyring: $KEYRING_NAME"
            exit 1
        }
    fi
    unset PSWD_HASH
    log_info "keyring created"
}  # make_keyring

function is_caps_lock () {
    caps_lock_status=$(xset -q | sed -n 's/^.*Caps Lock:\s*\(\S*\).*$/\1/p')
    if [[ "$caps_lock_status" == "on" ]]; then
        echo true
    else
        echo false
    fi
}

function shift_caps () {
    install_app xdotool
    xdotool key Caps_Lock
}
