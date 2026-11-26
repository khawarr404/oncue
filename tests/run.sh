#!/bin/bash
# Tests against a fake meeting: no microphone, PipeWire or speech model needed.
# Runs in a temporary ONCUE_HOME, so your real data is never touched.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/skills/oncue/scripts"
export ONCUE_HOME="$(mktemp -d)"
export ONCUE_NO_POPUP=1
PORT=$((20000 + RANDOM % 20000))
FAIL=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAIL=1; }
cleanup() {
  for p in "$ONCUE_HOME"/run/*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  [ -n "${FAKE:-}" ] && kill "$FAKE" 2>/dev/null
  rm -rf "$ONCUE_HOME"
}
trap cleanup EXIT

# 1. Syntax
for f in "$S"/*.sh "$REPO"/install.sh "$REPO"/tests/*.sh; do bash -n "$f" || fail "syntax $f"; done
python3 -m py_compile "$S/listen.py" "$S/dashboard.py" "$S/answer.py" "$S/float.py" && pass "syntax" || fail "python syntax"

# 2. Fake meeting: a session folder, LATEST pointer, and a stand-in listener process.
H="$ONCUE_HOME"; SESSION="$H/sessions/2026-01-01-1000"; T="$SESSION/transcript.txt"
mkdir -p "$SESSION" "$H/run"; : > "$T"; echo "$T" > "$H/sessions/LATEST"
printf 'Sam\nSem\n' > "$H/name.txt"; echo "roadmap" > "$H/topics.txt"
echo '{"model": "test", "beam": 1, "mic": true}' > "$SESSION/session.json"
sleep 600 & FAKE=$!; echo "$FAKE" > "$H/run/listen.pid"

bash "$S/watch.sh" > "$H/watch.out" 2>&1 &
sleep 1.5
cat >> "$T" <<'LINES'
[10:00:00] THEM: hi everyone, how was the weekend?
[10:00:05] THEM: Sam, can you share the status?
[10:00:10] ME: sure, one second
[10:00:20] THEM: what did the client say?
[10:02:00] THEM: did anyone see the game?
[10:02:05] THEM: is the roadmap ready for the next quarter?
[10:02:10] THEM: I like the roadmap. Anyone want coffee?
[10:02:15] THEM: Sem will handle the follow up
[10:02:20] THEM: they were speaking about samples
LINES
sleep 1.5
EXPECTED='[10:00:05] THEM: Sam, can you share the status?
[10:00:20] THEM: what did the client say?
[10:02:05] THEM: is the roadmap ready for the next quarter?
[10:02:15] THEM: Sem will handle the follow up'
[ "$(cat "$SESSION/questions.log" 2>/dev/null)" = "$EXPECTED" ] && pass "watch: alert rules" \
  || { fail "watch: alert rules"; echo "--- got:"; cat "$SESSION/questions.log"; }
[ "$(cat "$H/watch.out")" = "$EXPECTED" ] && pass "watch: stdout stream" || fail "watch: stdout stream"

# 3. next-question.sh: delivers everything pending, then NONE, then new lines, then STOPPED.
OUT=$(bash "$S/next-question.sh" 2)
[ "$(echo "$OUT" | grep -c '^QUESTION ')" = 4 ] && pass "next-question: pending batch" || { fail "next-question: pending batch"; echo "$OUT"; }
[ "$(bash "$S/next-question.sh" 2)" = "NONE" ] && pass "next-question: timeout" || fail "next-question: timeout"
echo "[10:03:00] THEM: Sam, what is the budget?" >> "$T"
sleep 1.5
OUT=$(bash "$S/next-question.sh" 2)
[ "$OUT" = "QUESTION [10:03:00] THEM: Sam, what is the budget?" ] && pass "next-question: new line kept between calls" || { fail "next-question: new line"; echo "$OUT"; }

# 4. Dashboard and notify.sh
bash "$S/notify.sh" "What is the budget?" "Within the plan we agreed; I'll send the exact figure today."
python3 "$S/dashboard.py" --port "$PORT" > /dev/null 2>&1 &
for _ in $(seq 1 30); do curl -s "127.0.0.1:$PORT/api/state" > "$H/state.json" 2>/dev/null && [ -s "$H/state.json" ] && break; sleep 0.2; done
python3 - "$H/state.json" <<'PY' && pass "dashboard: /api/state" || fail "dashboard: /api/state"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["live"] is True, s["live"]
assert s["model"] == "test"
assert s["questions_count"] == 5, s["questions_count"]
assert s["answers"][-1]["q"] == "What is the budget?", s["answers"]
assert len(s["lines"]) == 10, len(s["lines"])
PY
curl -s "127.0.0.1:$PORT/" | grep -q "oncue" && pass "dashboard: page" || fail "dashboard: page"

# 5. stop.sh stops listener and watcher; next-question then reports STOPPED.
bash "$S/stop.sh" > /dev/null
sleep 0.5
kill -0 "$FAKE" 2>/dev/null && fail "stop: listener still running" || pass "stop: listener"
[ -f "$H/run/watch.pid" ] && fail "stop: watcher pid left" || pass "stop: watcher"
[ "$(bash "$S/next-question.sh" 2)" = "STOPPED" ] && pass "next-question: STOPPED" || fail "next-question: STOPPED"
curl -s "127.0.0.1:$PORT/api/state" | grep -q '"live": false' && pass "dashboard: shows stopped" || fail "dashboard: shows stopped"

# 6. Real up.sh / listen.py / stop.sh with stand-in recorder and speech model.
bash "$REPO/tests/test_listener.sh" || FAIL=1

# 7. Quick actions and modes (dashboard POST endpoints, watch.sh, mode.sh).
bash "$REPO/tests/test_actions_modes.sh" || FAIL=1

# 8. Standalone answerer against a stand-in model server.
bash "$REPO/tests/test_answer.sh" || FAIL=1

# 9. Floating answer window: dashboard token file, local client POSTs, float.py logic (window only with a display).
bash "$REPO/tests/test_float.sh" || FAIL=1

[ "$FAIL" = 0 ] && echo "all tests passed" || { echo "some tests failed"; exit 1; }
