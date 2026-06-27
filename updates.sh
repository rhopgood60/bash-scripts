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
###############################################################################################
#
# system update script
#
###############################################################################################
#
#include file

include='distro_info.sh'
source_file=$(find "$HOME" \
  \( -path "$HOME/.docker" \
     -o -path "$HOME/docker" \
     -o -path "$HOME/*/db" \
     -o -path "$HOME/*/data" \) -prune -o \
  -type f -iname "$include" -print -quit 2>/dev/null)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

###############################################################################################
# for debugging
# echo $LINUX_CODENAME
# echo $LINUX_RELEASE
# echo $LINUX_RELEASE_MAJOR
# echo $LINUX_RELEASE_MINOR
# echo $LINUX_DISTRIBUTION
# echo $DESKTOP_SESSION
# echo $ARCH

#case $(hostname) in
#  Herman  ) ;; # main
#  Lilly   ) ;; # secondary
#  Eddie   ) ;; # tertiary
#  Spot    ) ;; # virtual
#  Grandpa ) ;; # laptop
#  Marylyn ) ;; # netbook
#  Igor    ) ;; # phone
#  *       ) printf "\033[1;33mNot configured for this machine - %s\033[0m\n" "$(hostname)"
#            exit 1;;
#esac

###############################################################################################
#
#set variables

starttime

TODAY="$(date --date="$(date --iso-8601)" +%s 2>/dev/null)"
UPDATEDATE="$(date --date="$(date -r "${0}" --iso-8601)" +%s 2>/dev/null)"

if [[ $(is_caps_lock) == "true" ]]; then
    shift_caps
fi

if [ "${TODAY}" -eq "${UPDATEDATE}" ]; then
    echo_colour Green
    echo "🛑 Skipping updates — already done today."
    endtime
    elapsedtime "$STARTTIME" "$ENDTIME"
    echo_colour Yellow
    read -t 10 -r -p "I am going to wait for 10 seconds only ... " USER_INPUT
    if [[ $? -ne 0 ]]; then
        echo    # prints a newline if read times out
    fi
    echo_colour NoColour
    exit
fi

echo 
echo_colour Blue "$PKGMGR packages"
echo_colour NoColour
sudo "$PKGMGR" "$UPDATE_ARG"
sudo "$PKGMGR" -y "$UPGRADE_ARG" --allow-downgrades.
sudo "$PKGMGR" -y autoremove --purge
sudo "$PKGMGR" -y clean
sudo "$PKGMGR" --fix-broken install
sudo deborphan | xargs sudo "$PKGMGR" remove --purge -y
current_kernel=$(uname -r)
mapfile -t old_kernels < <(dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$current_kernel" | grep -v "linux-image-generic")
if [[ ${#old_kernels[@]} -gt 0 ]]; then
    sudo "$PKGMGR" remove --purge -y "${old_kernels[@]}"
else
    echo "No old kernels found for removal."
fi


if command -v flatpak > /dev/null && flatpak --version > /dev/null; then
    echo
    echo_colour Blue 'flatpak packages' NoColour
    echo
echo
    sudo flatpak update -y
    sudo flatpak uninstall --unused
    sudo rm -rfv /var/tmp/flatpak-cache-*
fi

if command -v snap > /dev/null && snap --version > /dev/null; then
    echo
    echo_colour Blue 'snap packages' NoColour
    echo
echo
    sudo snap refresh
    sudo find /var/lib/snapd/cache/ -exec rm -vR {} \; 2>/dev/null
fi

echo
echo_colour Blue 'cleanup' NoColour
echo
sudo journalctl --vacuum-time=5d

CACHEDATE="$(date --date="$(date -r "${HOME}/.cache/thumbnails" --iso-8601)" +%s 2>/dev/null)"
if [[ ${CACHEDATE} -ge $(date -d "now - 30 days" +%s) ]]; then
    rm -rf "${HOME}"/.cache/thumbnails/*
    touch "${HOME}"/.cache/thumbnails
fi

touch "${0}"

endtime
echo_colour Green
elapsedtime "$STARTTIME" "$ENDTIME"

sleep 2
if [ -f /var/run/reboot-required ]; then 
    clear
    echo
    echo_colour Yellow 'reboot required' NoColour
    echo
    if DISPLAY=:0 kdialog --warningyesno "System required reboot. \n\n\nReboot now?"; then
        sudo reboot
    fi
fi

echo_colour Green
read -rp 'press enter'
#read -t 10 -r -p "I am going to wait for 10 seconds only ..."





exit

sudo apt update
sudo apt upgrade
sudo apt autoremove --purge
sudo apt clean
sudo apt --fix-broken install
sudo deborphan | xargs sudo apt remove --purge
current_kernel=$(uname -r)
mapfile -t old_kernels < <(dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$current_kernel" | grep -v "linux-image-generic")
echo ${#old_kernels[@]}
sudo flatpak update
sudo flatpak uninstall --unused
sudo rm -rfv /var/tmp/flatpak-cache-*
sudo snap refresh
sudo find /var/lib/snapd/cache/ -exec rm -vR {} \; 2>/dev/null
sudo journalctl --vacuum-time=5d
if [ -f /var/run/reboot-required ]; then 
    clear
    echo
    echo_colour Yellow 'reboot required' NoColour
    echo
    if DISPLAY=:0 kdialog --warningyesno "System required reboot. \n\n\nReboot now?"; then
        sudo reboot
    fi
fi
