#!/bin/bash
# Runs the real up.sh / listen.py / stop.sh path with stand-ins for pw-record and faster-whisper, from a copy
# of the repo under another folder name. No microphone or speech model needed; needs python3 with numpy.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY=$(command -v python3)
if ! "$PY" -c "import numpy" 2>/dev/null; then echo "SKIP listener test (python3 has no numpy)"; exit 0; fi
WORK="$(mktemp -d)"
export ONCUE_HOME="$WORK/home" ONCUE_NO_POPUP=1 ONCUE_PORT=$((20000 + RANDOM % 20000))
# The answerer must never reach a real model during tests: point it at a closed port.
export ONCUE_PROVIDER=ollama ONCUE_OLLAMA_URL="http://127.0.0.1:9" ONCUE_LLM_TIMEOUT=2
FAIL=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAIL=1; }
cleanup() {
  bash "$WORK/other-name/skills/oncue/scripts/stop.sh" --all > /dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

cp -r "$REPO" "$WORK/other-name"
S="$WORK/other-name/skills/oncue/scripts"
mkdir -p "$WORK/bin" "$WORK/py" "$ONCUE_HOME/.venv/bin"
ln -s "$PY" "$ONCUE_HOME/.venv/bin/python"

# Fake pw-record: 1.5 s of loud noise, then 1 s of silence, forever (16 kHz, 16-bit mono on stdout).
cat > "$WORK/bin/pw-record" <<'EOF'
#!/usr/bin/env python3
import os, sys, time
loud, quiet = os.urandom(48000), bytes(32000)
try:
    while True:
        sys.stdout.buffer.write(loud + quiet); sys.stdout.buffer.flush(); time.sleep(0.5)
except (BrokenPipeError, KeyboardInterrupt):
    pass
EOF
chmod +x "$WORK/bin/pw-record"
# Fake faster_whisper: every piece of speech becomes the same line.
cat > "$WORK/py/faster_whisper.py" <<'EOF'
class _Seg:
    text = " Sam, is the roadmap ready?"
class WhisperModel:
    def __init__(self, *a, **k): pass
    def transcribe(self, audio, **k): return [_Seg()], None
EOF
export PATH="$WORK/bin:$PATH" PYTHONPATH="$WORK/py"

bash "$S/up.sh" --answer > "$WORK/up.out" 2>&1
H="$ONCUE_HOME"
PID=$(cat "$H/run/listen.pid" 2>/dev/null)
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && pass "up.sh: listener running (pid file)" || { fail "up.sh: listener"; cat "$WORK/up.out" "$H/run/listen.log"; }
T=$(cat "$H/sessions/LATEST" 2>/dev/null)
[ -n "$T" ] && pass "up.sh: LATEST set" || fail "up.sh: LATEST set"
for _ in $(seq 1 20); do grep -q "THEM: Sam, is the roadmap ready?" "$T" 2>/dev/null && break; sleep 0.5; done
grep -q "^\[..:..:..\] THEM: Sam, is the roadmap ready?" "$T" 2>/dev/null && pass "listen.py: transcript lines" || fail "listen.py: transcript lines"
grep -q "^\[..:..:..\] ME: " "$T" && pass "listen.py: mic stream" || fail "listen.py: mic stream"
APID=$(cat "$H/run/answer.pid" 2>/dev/null)
[ -n "$APID" ] && kill -0 "$APID" 2>/dev/null && ! grep -q "unrecognized arguments" "$H/run/listen.log" \
  && pass "up.sh --answer: answerer running, flag not passed to listen.py" || { fail "up.sh --answer"; cat "$WORK/up.out"; }
OUT=$(bash "$S/next-question.sh" 10)
echo "$OUT" | grep -q "^QUESTION .*THEM: Sam, is the roadmap ready?" && pass "up.sh + next-question: question delivered" || { fail "next-question via up.sh"; echo "$OUT"; }

bash "$S/stop.sh" > /dev/null
sleep 1
kill -0 "$PID" 2>/dev/null && fail "stop.sh: listener still running" || pass "stop.sh: listener stopped"
[ -f "$H/run/listen.pid" ] && fail "stop.sh: pid file left" || pass "stop.sh: pid file removed"
pgrep -f "$WORK/bin/pw-record" > /dev/null && fail "stop.sh: recorder left running" || pass "stop.sh: recorders stopped"
[ -n "$APID" ] && ! kill -0 "$APID" 2>/dev/null && [ ! -f "$H/run/answer.pid" ] && pass "stop.sh: answerer stopped" || fail "stop.sh: answerer"

[ "$FAIL" = 0 ] || exit 1
