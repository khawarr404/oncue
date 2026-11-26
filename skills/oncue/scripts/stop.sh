#!/bin/bash
# Stops the listener and the question watcher. The transcript stays in the sessions folder, and the
# dashboard keeps showing the finished meeting. --all also stops the dashboard.
source "$(dirname "$0")/_lib.sh"
stop_pid listen
stop_pid watch
[ "$1" = "--all" ] && stop_pid dashboard
echo "stopped"
