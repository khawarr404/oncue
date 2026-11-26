#!/bin/bash
# Shared paths and helpers for the oncue scripts. Sourced, not run.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${ONCUE_HOME:-$HOME/oncue}"
RUN_DIR="$HOME_DIR/run"
export ONCUE_HOME="$HOME_DIR"
mkdir -p "$RUN_DIR" "$HOME_DIR/sessions"

# alive NAME: true if run/NAME.pid holds the id of a running process.
alive() {
  local pid
  pid=$(cat "$RUN_DIR/$1.pid" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# stop_pid NAME: stop the process in run/NAME.pid (and its children), then remove the file.
stop_pid() {
  local pid
  pid=$(cat "$RUN_DIR/$1.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    pkill -TERM -P "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
    echo "stopped $1"
  fi
  rm -f "$RUN_DIR/$1.pid"
}

# latest_transcript: path of the current meeting's transcript.txt, empty if none.
latest_transcript() { cat "$HOME_DIR/sessions/LATEST" 2>/dev/null; }
