#!/bin/sh
#
# This script runs when an SSH session opens/closes.
# It starts/stops a logind sleep inhibitor, blocking automatic sleep
# (e.g. GNOME auto-suspend) while SSH sessions are active.
# Explicit suspend (sudo systemctl suspend) still works because
# root has polkit permission to ignore inhibitors.
#

LOCKFILE=/run/ssh-session.lock
COUNTER=/run/ssh-session-count

(
    flock -x 200

    count=$(cat "$COUNTER" 2>/dev/null || echo 0)

    case "$PAM_TYPE" in
        open_session)
            count=$((count + 1))
            echo "$count" > "$COUNTER"
            if [ "$count" -eq 1 ]; then
                logger "SSH session opened (count=${count}), starting sleep inhibitor"
                systemctl start ssh-sleep-inhibitor.service
            fi
            ;;

        close_session)
            count=$((count - 1))
            [ "$count" -lt 0 ] && count=0
            echo "$count" > "$COUNTER"
            if [ "$count" -eq 0 ]; then
                logger "Last SSH session closed, stopping sleep inhibitor"
                systemctl stop ssh-sleep-inhibitor.service
            fi
            ;;
    esac
) 200>"$LOCKFILE"
