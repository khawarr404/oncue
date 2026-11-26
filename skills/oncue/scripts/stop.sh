#!/bin/bash
# Stops the listener, the question watcher, the standalone answerer and the floating answer window (if
# running). The transcript stays in the sessions folder, and the dashboard keeps showing the finished meeting.
# --all also stops the dashboard.
source "$(dirname "$0")/_lib.sh"
stop_pid listen
stop_pid watch
stop_pid answer
stop_pid float
[ "$1" = "--all" ] && stop_pid dashboard
echo "stopped"
