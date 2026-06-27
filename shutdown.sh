#!/usr/bin/env bash
SCRIPTPATH="$(dirname "$(cd "${0%/*}" 2>/dev/null; echo "$PWD"/"${0##*/}")")"
#*******************************************************************************
#
# ssh shutdown
#
#*******************************************************************************

SESSION_TYPE=local
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
  SESSION_TYPE=remote/ssh
# many other tests omitted
else
  case $(ps -o comm= -p "$PPID") in
    sshd|*/sshd) SESSION_TYPE=remote/ssh;;
  esac
fi

if [[ "$SESSION_TYPE" == "remote/ssh" ]]; then
    sudo shutdown now && exit
fi
