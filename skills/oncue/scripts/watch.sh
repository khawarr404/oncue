#!/bin/bash
# Prints questions meant for the user as they appear in the live transcript (one line per alert) and appends
# each to sessions/<session>/questions.log (the dashboard and next-question.sh read it).
# Made for a streaming tool such as Claude Code's Monitor; up.sh also runs it detached for other agents.
#
# A THEM line alerts when it:
#   1. contains the user's name or a usual mis-hearing of it (name.txt: the name on line 1, then one
#      mis-hearing per line, e.g. Siobhan / Shivon / Chevon), or
#   2. has "?" and the user (a ME line) spoke in the last 60 s, or
#   3. has a question (a sentence ending in "?") that itself contains a project word from topics.txt
#      (optional; comma or line separated). Same sentence, because long chatter often has a "?" in one
#      place and a project word somewhere else, or
#   4. says "can you / could you / why / how" and the user spoke in the last 60 s.
# Everything else (chatter between other people) is ignored.
# ACTION lines (quick actions the dashboard writes, e.g. "[10:05:00] ACTION: recap") always pass through.
source "$(dirname "$0")/_lib.sh"
words() { [ -f "$1" ] && tr ',\n' '||' < "$1" | tr -s '|' | sed 's/^|//; s/|$//'; }
NAMES="${ONCUE_NAME:-$(words "$HOME_DIR/name.txt")}"
TOPICS="$(words "$HOME_DIR/topics.txt")"

for _ in $(seq 1 180); do [ -f "$HOME_DIR/sessions/LATEST" ] && break; sleep 1; done
F=$(latest_transcript)
[ -n "$F" ] || { echo "no meeting running (start.sh or up.sh first)" >&2; exit 1; }
for _ in $(seq 1 60); do [ -f "$F" ] && break; sleep 1; done
QLOG="$(dirname "$F")/questions.log"

# Another watcher already writes questions.log: follow that file instead of detecting twice.
if alive watch && [ "$(cat "$RUN_DIR/watch.pid")" != "$$" ]; then
  touch "$QLOG"
  exec tail -n0 -F --pid="$(cat "$RUN_DIR/watch.pid")" "$QLOG" 2>/dev/null
fi
echo $$ > "$RUN_DIR/watch.pid"
trap '[ "$(cat "$RUN_DIR/watch.pid" 2>/dev/null)" = "$$" ] && rm -f "$RUN_DIR/watch.pid"' EXIT

# mawk needs -W interactive to read the pipe line by line; fflush() sends each alert out at once.
AWK_OPTS=""; awk -W version 2>/dev/null | grep -q mawk && AWK_OPTS="-W interactive"
# --pid: tail ends when this script is stopped instead of lingering.
tail -n0 -F --pid=$$ "$F" 2>/dev/null | awk $AWK_OPTS -v names="$NAMES" -v topics="$TOPICS" -v qlog="$QLOG" '
  # Match " word " on a copy with punctuation turned into spaces: "Sam?" matches, while "peak" does not
  # match "speaking". Multi-word entries ("road map", "data pipeline") work the same way.
  function plain(s) { s = tolower(s); gsub(/[^a-z0-9]+/, " ", s); gsub(/^ +| +$/, "", s); return " " s " " }
  function any(text, list,   n, a, i, w) {
    n = split(list, a, "|")
    for (i = 1; i <= n; i++) { w = plain(a[i]); if (w != "  " && index(text, w)) return 1 }
    return 0
  }
  function topical(text,   s, n, parts, i) {
    s = text; gsub(/[.!]/, "|", s); gsub(/\?/, "?|", s); n = split(s, parts, "|")
    for (i = 1; i <= n; i++) if (parts[i] ~ /\?$/ && any(plain(parts[i]), topics)) return 1
    return 0
  }
  function secs(t) { return substr(t, 2, 2) * 3600 + substr(t, 5, 2) * 60 + substr(t, 8, 2) }
  BEGIN { last_me = -1 }
  # Quick actions from the dashboard ("[10:05:00] ACTION: recap") always pass straight through.
  /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ACTION: / { print; fflush(); print >> qlog; fflush(qlog); next }
  /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ME: / { last_me = secs($1); next }
  /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] THEM: / {
    text = substr($0, index($0, "THEM: ") + 6); p = plain(text)
    recent = 0
    if (last_me >= 0) { d = secs($1) - last_me; if (d < 0) d += 86400; recent = (d <= 60) }
    ask = index(text, "?") > 0
    if (any(p, names) || (ask && recent) || (ask && topical(text)) ||
        (recent && (index(p, " can you ") || index(p, " could you ") || index(p, " why ") || index(p, " how ")))) {
      print; fflush()
      print >> qlog; fflush(qlog)
    }
  }'
