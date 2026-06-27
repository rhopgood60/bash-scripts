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

include='bash_functions'
source_file=$(find "$HOME" -path "$HOME/.docker/immich-app/postgres" -prune -o -type f -iname "$include" -print -quit)
if [[ -n "$source_file" ]]; then
    source "$source_file"
else
    echo "❌ $include not found"
    exit 1
fi

###############################################################################################

starttime

TODAY="$(date --date="$(date --iso-8601)" +%s 2>/dev/null)"
UPDATEDATE="$(date --date="$(date -r "${SCRIPTPATH/updates.sh}" --iso-8601)" +%s 2>/dev/null)"

#if [ "${TODAY}" -eq "${UPDATEDATE}" ]; then
#    echo_colour Green
#    echo "🛑 Skipping maintenance — already done today."
#    endtime
#    elapsedtime "$STARTTIME" "$ENDTIME"
#   echo $(date)
#    echo_colour NoColour
#    exit
#fi

REMOTESERVER="Eddie"
TEST=""
BACKUP=""
for ((i = 1; i <= $#; i++ )); do
    case $i in
        1 ) BACKUP="$(echo "${1:-}" | tr '[:lower:]' '[:upper:]')"
            BACKUP="${BACKUP:0:2}"
            if [[ "$BACKUP" != "TO" && "$BACKUP" != "FR" ]]; then 
                echo "Invalid backup options"
                echo "valid options = to/TO or fr/FR/from/FROM"
                exit
            fi
            ;;
        2 ) TEST="$(echo "${2:-}" | tr '[:lower:]' '[:upper:]')"
            ;;
    esac
done

echo "p1 - *$TEST*"
echo "p2 - *$BACKUP*"

if [[ "${TEST}" == "" ]]; then
    echo "updates"
#    x-terminal-emulator -e "${SCRIPTPATH}/updates.sh" &
    "${SCRIPTPATH}/updates.sh" 
fi

install_app nmap

case "${BACKUP}" in
    FR ) echo "from server backup"
         macadd="$(sudo nmap -f -sn 192.168.1.60-100 | grep "Raspberry" | awk '{print $3}')"
         REMOTEHOST="$(arp -a | grep "${macadd,,}" | awk '{print $2}')"
         REMOTEHOST="${REMOTEHOST#*\(}"
         REMOTEHOST="${REMOTEHOST%\)*}"
         INTERFACE="$(ip -o route get to 8.8.8.8 | awk '{print $5}')"
         if [ -z "$INTERFACE" ]; then
             exit 1
         fi
         SOURCEIP="$(ip -o route get to 8.8.8.8 | awk '{print $7}')"
         rsync -au "${SCRIPTPATH}/backup_include.sh" "${SCRIPTPATH}/bash_functions" "${USER}@${REMOTEHOST}:/home/hermes/bin/"
         ssh "${USER}@${REMOTEHOST}" "bash -s" < "${SCRIPTPATH}/backupssh_fr.sh" "${SOURCEIP}" "${HOSTNAME}" "${USER}"
         ;;
    TO ) echo "to server backup"
         "${SCRIPTPATH}/bin/backupssh_to.sh"
         ;;
    *  ) echo "local backup"
#         x-terminal-emulator -e "${SCRIPTPATH}/backup.sh" &
         "${SCRIPTPATH}/backup.sh"
         ;;
esac

endtime
elapsedtime "$STARTTIME" "$ENDTIME"
echo $(date)
