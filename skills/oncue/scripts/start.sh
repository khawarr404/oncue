#!/bin/bash
# Starts the listener in the foreground (runs until stopped). Use this when your agent can run a command in
# the background itself (Claude Code: Bash run_in_background). Otherwise use up.sh, which detaches.
# Extra arguments go to listen.py, e.g. --no-mic or --language de.
source "$(dirname "$0")/_lib.sh"
if alive listen; then echo "already listening (stop.sh first)"; exit 0; fi
[ -x "$HOME_DIR/.venv/bin/python" ] || { echo "not set up yet: run scripts/setup.sh"; exit 1; }
# Clear the pointer to the previous meeting so watch.sh waits for this one.
rm -f "$HOME_DIR/sessions/LATEST"
exec "$HOME_DIR/.venv/bin/python" "$SKILL_DIR/scripts/listen.py" "$@"
