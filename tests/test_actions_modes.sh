#!/bin/bash
# Quick actions and modes: the dashboard's POST endpoints (token, host and name checks), ACTION lines through
# watch.sh and next-question.sh, and mode.sh. Fake meeting in a temporary ONCUE_HOME; no audio needed.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/skills/oncue/scripts"
export ONCUE_HOME="$(mktemp -d)"
export ONCUE_NO_POPUP=1
PORT=$((20000 + RANDOM % 20000))
URL="http://127.0.0.1:$PORT"
FAIL=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAIL=1; }
cleanup() {
  for p in "$ONCUE_HOME"/run/*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  [ -n "${FAKE:-}" ] && kill "$FAKE" 2>/dev/null
  rm -rf "$ONCUE_HOME"
}
trap cleanup EXIT
# wait_for "test command" [tries]: polls every 0.25 s.
wait_for() { for _ in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.25; done; return 1; }

H="$ONCUE_HOME"; SESSION="$H/sessions/2026-01-01-1100"; T="$SESSION/transcript.txt"
mkdir -p "$SESSION" "$H/run"; : > "$T"; echo "$T" > "$H/sessions/LATEST"
printf 'Sam\n' > "$H/name.txt"
echo '{"model": "test", "beam": 1, "mic": true}' > "$SESSION/session.json"
sleep 600 & FAKE=$!; echo "$FAKE" > "$H/run/listen.pid"

# --- mode.sh ---
OUT=$(bash "$S/mode.sh")
for m in meeting interview sales client standup negotiation; do
  echo "$OUT" | grep -q "^[ *] $m\$" || fail "mode.sh: lists $m"
done
echo "$OUT" | grep -q '^\* meeting$' && pass "mode.sh: lists built-in modes, meeting is the default" || { fail "mode.sh: default"; echo "$OUT"; }
bash "$S/mode.sh" Interview > /dev/null && [ "$(cat "$H/mode.txt")" = interview ] && pass "mode.sh: set" || fail "mode.sh: set"
bash "$S/mode.sh" | grep -q '^\* interview$' && pass "mode.sh: marks current" || fail "mode.sh: marks current"
if bash "$S/mode.sh" nosuchmode > /dev/null 2>&1 || bash "$S/mode.sh" ../etc > /dev/null 2>&1; then
  fail "mode.sh: unknown mode accepted"
else
  [ "$(cat "$H/mode.txt")" = interview ] && pass "mode.sh: unknown mode refused" || fail "mode.sh: unknown mode changed mode.txt"
fi
mkdir -p "$H/modes"; echo "# Pitch mode" > "$H/modes/pitch.md"; echo "# My meeting mode" > "$H/modes/meeting.md"
OUT=$(bash "$S/mode.sh")
echo "$OUT" | grep -q '^  pitch .*(yours)$' && echo "$OUT" | grep -q '^  meeting .*replaces' \
  && pass "mode.sh: own modes listed, override marked" || { fail "mode.sh: own modes"; echo "$OUT"; }
bash "$S/mode.sh" meeting > /dev/null
[ "$(bash "$S/mode.sh" --path)" = "$H/modes/meeting.md" ] && pass "mode.sh: --path prefers your own file" || fail "mode.sh: --path"

# --- dashboard: token and checks ---
bash "$S/watch.sh" > "$H/watch.out" 2>&1 &
python3 "$S/dashboard.py" --port "$PORT" > /dev/null 2>&1 &
wait_for 'curl -sf "$URL/api/state" > /dev/null' || fail "dashboard: did not start"
wait_for '[ -f "$H/run/watch.pid" ]' || fail "watch: did not start"
TOKEN=$(curl -s "$URL/" | sed -n 's/.*name="oncue-token" content="\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] && [ "$TOKEN" != "__ONCUE_TOKEN__" ] && pass "dashboard: token in page" || fail "dashboard: token in page"
curl -s "$URL/api/state" | grep -qF "$TOKEN" && fail "dashboard: token leaked in /api/state" || pass "dashboard: token not in /api/state"

# post PATH JSON [curl args...]: prints the HTTP status code.
post() { local p="$1" d="$2"; shift 2; curl -s -o "$H/post.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$d" "$@" "$URL$p"; }
[ "$(post /api/action '{"action":"recap"}')" = 403 ] && pass "action: no token -> 403" || fail "action: no token"
[ "$(post /api/action '{"action":"recap"}' -H 'X-Oncue-Token: wrong')" = 403 ] && pass "action: wrong token -> 403" || fail "action: wrong token"
[ "$(post /api/action '{"action":"recap"}' -H "X-Oncue-Token: $TOKEN" -H "Host: attacker.example:$PORT")" = 403 ] \
  && pass "action: other host name -> 403" || fail "action: other host name"
[ "$(post /api/action '{"action":"recap"}' -H "X-Oncue-Token: $TOKEN" -H 'Origin: https://attacker.example')" = 403 ] \
  && pass "action: other origin -> 403" || fail "action: other origin"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: attacker.example:$PORT" "$URL/")" = 403 ] \
  && pass "page: other host name -> 403" || fail "page: other host name"
[ "$(post /api/action '{"action":"rm -rf"}' -H "X-Oncue-Token: $TOKEN")" = 400 ] && pass "action: unknown action -> 400" || fail "action: unknown action"
[ "$(post /api/action 'not json' -H "X-Oncue-Token: $TOKEN")" = 400 ] && pass "action: bad body -> 400" || fail "action: bad body"
grep -q "ACTION" "$T" && fail "action: refused request wrote to the transcript" || pass "action: refused requests write nothing"

# --- quick action end to end ---
echo "[11:00:05] THEM: Sam, can you share the status?" >> "$T"
wait_for 'grep -q "share the status" "$SESSION/questions.log" 2>/dev/null' || fail "watch: question"
CODE=$(post /api/action '{"action":"recap"}' -H "X-Oncue-Token: $TOKEN" -H "Origin: $URL")
[ "$CODE" = 200 ] && grep -q '^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ACTION: recap$' "$T" \
  && pass "action: recap -> ACTION line in transcript" || { fail "action: recap"; cat "$H/post.out"; }
wait_for 'grep -q "ACTION: recap" "$SESSION/questions.log" 2>/dev/null' && pass "watch: ACTION line in questions.log" || fail "watch: ACTION to questions.log"
grep -q "ACTION: recap" "$H/watch.out" && pass "watch: ACTION line streamed (Monitor path)" || fail "watch: ACTION streamed"
OUT=$(bash "$S/next-question.sh" 2)
[ "$(echo "$OUT" | grep -c '^QUESTION ')" = 2 ] && echo "$OUT" | grep -q '^QUESTION \[..:..:..\] ACTION: recap$' \
  && pass "next-question: delivers ACTION lines" || { fail "next-question: ACTION"; echo "$OUT"; }

curl -s "$URL/api/state" > "$H/state.json"
python3 - "$H/state.json" <<'PY' && pass "dashboard: ACTION kept out of transcript and question count" || fail "dashboard: state with ACTION"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["questions_count"] == 1, s["questions_count"]
assert s["actions_count"] == 1, s["actions_count"]
assert len(s["lines"]) == 1 and s["lines"][0]["who"] == "THEM", s["lines"]
assert s["pending"] and s["pending"]["who"] == "ACTION" and s["pending"]["text"] == "recap", s["pending"]
PY

# A multi-line answer (recap) through notify.sh: blank lines dropped, all lines kept by the dashboard.
bash "$S/notify.sh" "Recap" "- status shared

- budget open"
grep -q '^  \*\*Say:\*\* - status shared$' "$SESSION/answers.md" && grep -q '^    - budget open$' "$SESSION/answers.md" \
  && pass "notify: multi-line answer format" || { fail "notify: multi-line"; cat "$SESSION/answers.md"; }
curl -s "$URL/api/state" > "$H/state.json"
python3 - "$H/state.json" <<'PY' && pass "dashboard: multi-line answer, pending cleared" || fail "dashboard: multi-line answer"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["answers"][-1] == {"time": s["answers"][-1]["time"], "q": "Recap", "say": "- status shared\n- budget open"}, s["answers"]
assert s["pending"] is None, s["pending"]
PY

# --- dashboard: mode ---
[ "$(post /api/mode '{"mode":"sales"}')" = 403 ] && pass "mode api: no token -> 403" || fail "mode api: no token"
[ "$(post /api/mode '{"mode":"../../x"}' -H "X-Oncue-Token: $TOKEN")" = 400 ] && pass "mode api: unknown mode -> 400" || fail "mode api: unknown"
[ "$(post /api/mode '{"mode":"sales"}' -H "X-Oncue-Token: $TOKEN")" = 200 ] && [ "$(cat "$H/mode.txt")" = sales ] \
  && pass "mode api: switch" || fail "mode api: switch"
curl -s "$URL/api/state" > "$H/state.json"
python3 - "$H/state.json" <<'PY' && pass "dashboard: /api/state shows mode" || fail "dashboard: state mode"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["mode"] == "sales", s["mode"]
assert {"meeting", "interview", "sales", "client", "standup", "negotiation", "pitch"} <= set(s["modes"]), s["modes"]
PY
bash "$S/mode.sh" | grep -q '^\* sales$' && pass "mode.sh: sees the dashboard's switch" || fail "mode.sh: after api switch"

# --- not listening: actions are refused ---
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null
[ "$(post /api/action '{"action":"answer"}' -H "X-Oncue-Token: $TOKEN")" = 409 ] && pass "action: not listening -> 409" || fail "action: not listening"

[ "$FAIL" = 0 ] || exit 1
