#!/bin/bash
# Starts everything detached and returns at once: the listener, the question watcher (writes questions.log)
# and the live dashboard. For agents that cannot keep a command running in the background or stream its
# output (Cursor, Codex, Gemini CLI, Copilot, ...). Then loop on next-question.sh.
# Extra arguments go to listen.py, e.g. --no-mic. Logs: $ONCUE_HOME/run/*.log
source "$(dirname "$0")/_lib.sh"
S="$SKILL_DIR/scripts"
[ -x "$HOME_DIR/.venv/bin/python" ] || { echo "not set up yet: run scripts/setup.sh"; exit 1; }

if alive listen; then
  echo "listener: already running"
else
  rm -f "$HOME_DIR/sessions/LATEST"
  stop_pid watch > /dev/null   # a watcher left from an earlier meeting would follow the old transcript
  nohup "$HOME_DIR/.venv/bin/python" "$S/listen.py" "$@" > "$RUN_DIR/listen.log" 2>&1 < /dev/null &
  echo "listener: started"
fi

if alive watch; then
  echo "watcher: already running"
else
  nohup bash "$S/watch.sh" > /dev/null 2> "$RUN_DIR/watch.log" < /dev/null &
  echo "watcher: started"
fi

if alive dashboard; then
  echo "dashboard: already running"
else
  nohup python3 "$S/dashboard.py" > "$RUN_DIR/dashboard.log" 2>&1 < /dev/null &
  echo "dashboard: started"
fi

# Wait (up to 60 s, the speech model loads first) for the new meeting's transcript.
for _ in $(seq 1 60); do F=$(latest_transcript); [ -n "$F" ] && [ -f "$F" ] && break; sleep 1; done
F=$(latest_transcript)
if [ -n "$F" ]; then echo "transcript: $F"; else echo "listener not ready yet; see $RUN_DIR/listen.log"; fi
echo "dashboard: http://127.0.0.1:${ONCUE_PORT:-8765}"
