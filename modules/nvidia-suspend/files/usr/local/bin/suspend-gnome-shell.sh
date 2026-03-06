#!/bin/bash
# Stop gnome-shell before suspend so it releases the NVIDIA driver,
# then resume it after wake. Called by gnome-shell-suspend/resume services.

case "$1" in
    suspend)
        killall -STOP gnome-shell
        ;;
    resume)
        killall -CONT gnome-shell
        ;;
esac
