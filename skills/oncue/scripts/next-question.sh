#!/bin/bash
# Waits for the next question meant for the user and prints it, then exits. For agents that run one shell
# command at a time and cannot stream output (Cursor, Codex, Gemini CLI, Copilot, ...): call it in a loop.
# Needs the watcher running (up.sh starts it).
#
# Usage: next-question.sh [timeout_seconds]   (default 240)
# Prints one of:
#   QUESTION [10:02:13] THEM: why did you pick this tool?   (one line per question; several if they piled up)
#   NONE     nothing new before the timeout: call again
#   STOPPED  the listener is not running: the meeting is over (or was never started)
# A read position is kept per meeting, so a question that arrives between two calls is never lost.
source "$(dirname "$0")/_lib.sh"
TIMEOUT="${1:-240}"
F=$(latest_transcript)
if [ -z "$F" ]; then echo "STOPPED"; exit 0; fi
QLOG="$(dirname "$F")/questions.log"
OFFSET_FILE="$(dirname "$F")/.read_offset"

read_new() {
  local done total
  done=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
  total=0; [ -f "$QLOG" ] && total=$(wc -l < "$QLOG")
  if [ "$total" -gt "$done" ]; then
    tail -n +"$((done + 1))" "$QLOG" | head -n "$((total - done))" | sed 's/^/QUESTION /'
    echo "$total" > "$OFFSET_FILE"
    return 0
  fi
  return 1
}

alive listen && ! alive watch && echo "WARNING watcher not running, no questions will arrive: run up.sh again"
end=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$end" ]; do
  read_new && exit 0
  if ! alive listen; then read_new || echo "STOPPED"; exit 0; fi
  sleep 1
done
echo "NONE"
