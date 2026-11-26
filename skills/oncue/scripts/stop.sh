#!/bin/bash
# Stops the listener, the question watcher and the standalone answerer (if running). The transcript stays in
# the sessions folder, and the dashboard keeps showing the finished meeting. --all also stops the dashboard.
source "$(dirname "$0")/_lib.sh"
stop_pid listen
stop_pid watch
stop_pid answer
[ "$1" = "--all" ] && stop_pid dashboard
echo "stopped"
