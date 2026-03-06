#!/bin/sh
#
# This script runs when an SSH session opens/closes.
# It starts/stops a logind sleep inhibitor, blocking automatic sleep
# (e.g. GNOME auto-suspend) while SSH sessions are active.
# Explicit suspend (sudo systemctl suspend) still works because
# root has polkit permission to ignore inhibitors.
#
# Inspired by: https://unix.stackexchange.com/a/136552/84197 and
#              https://askubuntu.com/a/954943/388360

num_ssh=$(netstat -nt | awk '$4 ~ /:22$/ && $6 == "ESTABLISHED"' | wc -l)

case "$PAM_TYPE" in
    open_session)
        if [ "${num_ssh}" -gt 1 ]; then
            exit 0
        fi
        logger "SSH session opened, starting sleep inhibitor (num_ssh=${num_ssh})"
        systemctl start ssh-sleep-inhibitor.service
        ;;

    close_session)
        if [ "${num_ssh}" -ne 0 ]; then
            exit 0
        fi
        logger "Last SSH session closed, stopping sleep inhibitor (num_ssh=${num_ssh})"
        systemctl stop ssh-sleep-inhibitor.service
        ;;

    *)
        exit 0
esac
