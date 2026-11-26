#!/bin/bash
# Standalone answerer (answer.py) against a stand-in model server (standard library), so no Ollama, API key
# or network is needed. Temporary ONCUE_HOME.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/skills/oncue/scripts"
WORK="$(mktemp -d)"
export ONCUE_HOME="$WORK/home" ONCUE_NO_POPUP=1 ONCUE_LLM_TIMEOUT=5
unset ONCUE_PROVIDER ONCUE_LLM_MODEL ANTHROPIC_API_KEY OPENAI_API_KEY OPENAI_BASE_URL ANTHROPIC_BASE_URL
PORT=$((20000 + RANDOM % 20000))
export ONCUE_OLLAMA_URL="http://127.0.0.1:$PORT"
FAIL=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAIL=1; }
cleanup() {
  for p in "$ONCUE_HOME"/run/*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  [ -n "${STUB:-}" ] && kill "$STUB" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT
wait_for() { for _ in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.25; done; return 1; }

# Stand-in model server: answers Ollama, Anthropic and OpenAI-style requests with the text in reply.txt
# (or HTTP 401 echoing the key, if reply.txt says 401), and records each request in requests.jsonl.
cat > "$WORK/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port, reply_file, log_file = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)))
        auth = self.headers.get("Authorization") or self.headers.get("x-api-key") or ""
        with open(log_file, "a") as f:
            f.write(json.dumps({"path": self.path, "auth": auth, "version": self.headers.get("anthropic-version") or "",
                                "body": body}) + "\n")
        reply = open(reply_file).read()
        if reply == "401":
            code, out = 401, {"error": {"message": "Incorrect API key provided: " + auth}}
        elif self.path == "/api/chat":
            code, out = 200, {"model": body["model"], "message": {"role": "assistant", "content": reply}, "done": True}
        elif self.path == "/v1/messages":
            code, out = 200, {"content": [{"type": "text", "text": reply}]}
        elif self.path == "/v1/chat/completions":
            code, out = 200, {"choices": [{"message": {"role": "assistant", "content": reply}}]}
        else:
            code, out = 404, {}
        data = json.dumps(out).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a):
        pass
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PY
REPLY="$WORK/reply.txt"; REQS="$WORK/requests.jsonl"
start_stub() {
  python3 "$WORK/stub.py" "$PORT" "$REPLY" "$REQS" > /dev/null 2>&1 & STUB=$!
  wait_for 'curl -s -o /dev/null -X POST -d "{}" "http://127.0.0.1:$PORT/x"' || fail "stub server did not start"
}
reply() { printf '%s' "$1" > "$REPLY"; }
answers() { grep -c '^- \*\*Q (' "$SESSION/answers.md" 2>/dev/null || true; }
requests_with() { grep -c "$1" "$REQS" 2>/dev/null || true; }

# Fake meeting with notes, prep and interview mode.
H="$ONCUE_HOME"; SESSION="$H/sessions/2026-01-01-1200"; T="$SESSION/transcript.txt"; Q="$SESSION/questions.log"
mkdir -p "$SESSION" "$H/run"; echo "$T" > "$H/sessions/LATEST"
echo "Sam" > "$H/name.txt"
printf '# Context\n- MARKER-CONTEXT: release planned for Friday\n' > "$H/CONTEXT.md"
printf '# Prep\n- MARKER-PREP: ask about their rollout\n' > "$H/prep.md"
echo interview > "$H/mode.txt"
printf '[12:00:00] ME: that is the plan\n[12:00:05] THEM: Sam, when do we ship?\n' > "$T"
reply "We ship on Friday."
start_stub

# A proxy in the environment must not catch requests to the local model.
http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 python3 "$S/answer.py" > "$WORK/answer.out" 2>&1 &
wait_for '[ -f "$SESSION/.answer_offset" ]' || fail "answer.py: did not start"
[ -f "$H/run/answer.pid" ] && kill -0 "$(cat "$H/run/answer.pid")" 2>/dev/null && pass "answer.py: running (pid file)" || fail "answer.py: pid file"

# 1. A question gets an answer in the exact answers.md format.
echo "[12:00:05] THEM: Sam, when do we ship?" >> "$Q"
wait_for '[ "$(answers)" = 1 ]' || fail "answer.py: no answer written"
python3 - "$SESSION/answers.md" <<'PY' && pass "answer.py: answer in answers.md format" || { fail "answer.py: format"; cat "$SESSION/answers.md"; }
import re, sys
text = open(sys.argv[1]).read()
assert re.fullmatch(r"- \*\*Q \(\d\d:\d\d:\d\d\):\*\* Sam, when do we ship\?\n  \*\*Say:\*\* We ship on Friday\.\n\n", text), repr(text)
PY
python3 - "$REQS" <<'PY' && pass "answer.py: prompt has notes, prep, mode and transcript" || fail "answer.py: prompt contents"
import json, sys
reqs = [json.loads(l) for l in open(sys.argv[1])]
r = [x for x in reqs if "when do we ship" in json.dumps(x)][-1]
b = r["body"]
assert r["path"] == "/api/chat" and b["model"] == "llama3.2" and b["stream"] is False, r
system, user = b["messages"][0]["content"], b["messages"][1]["content"]
assert "MARKER-CONTEXT" in system and "MARKER-PREP" in system and "Interview mode" in system, system
assert "The user is Sam" in system
assert "[12:00:00] ME: that is the plan" in user and "SKIP" in user, user
PY

# 2. The model says SKIP: nothing is written.
reply "SKIP"
echo "[12:00:20] THEM: Sam, nice weekend?" >> "$Q"
wait_for 'grep -q "skipped" "$H/run/answer.log" 2>/dev/null' && [ "$(answers)" = 1 ] \
  && pass "answer.py: SKIP writes nothing" || fail "answer.py: SKIP"

# 3. Quick actions: recap (multi-line) and answer (Q/SAY reply).
reply "- release on Friday

- rollout still open"
echo "[12:00:30] ACTION: recap" >> "$Q"
wait_for '[ "$(answers)" = 2 ]' || fail "answer.py: recap not written"
reply "Q: When do we ship?
SAY: Friday, as planned."
echo "[12:00:40] ACTION: answer" >> "$Q"
wait_for '[ "$(answers)" = 3 ]' || fail "answer.py: answer action not written"
PYTHONPATH="$S" python3 - <<'PY' && pass "answer.py: recap and answer actions shown on the dashboard" || fail "answer.py: actions"
import dashboard
a = dashboard.state()["answers"]
assert a[1]["q"] == "Recap" and a[1]["say"] == "- release on Friday\n- rollout still open", a[1]
assert a[2]["q"] == "When do we ship?" and a[2]["say"] == "Friday, as planned.", a[2]
PY
python3 - "$REQS" <<'PY' && pass "answer.py: recap prompt covers the last 5 minutes" || fail "answer.py: recap prompt"
import json, sys
reqs = [json.loads(l)["body"].get("messages", [{}])[-1].get("content", "") for l in open(sys.argv[1])]
assert any("last 5 minutes" in u and "bullets" in u and "[12:00:00] ME: that is the plan" in u for u in reqs)
PY

# 4. Own read position: next-question.sh still gets every line, and the two offsets stay apart.
[ "$(cat "$SESSION/.answer_offset")" = 4 ] && [ ! -f "$SESSION/.read_offset" ] \
  && pass "answer.py: own offset file, .read_offset untouched" || fail "answer.py: offsets"
OUT=$(bash "$S/next-question.sh" 1)
[ "$(echo "$OUT" | grep -c '^QUESTION ')" = 4 ] && [ "$(cat "$SESSION/.read_offset")" = 4 ] && [ "$(cat "$SESSION/.answer_offset")" = 4 ] \
  && pass "next-question: unaffected by the answerer" || { fail "next-question with answerer"; echo "$OUT"; }

# 5. Model server down: error logged, loop survives and answers once it is back.
kill "$STUB"; wait "$STUB" 2>/dev/null
echo "[12:01:00] THEM: Sam, what is the budget?" >> "$Q"
wait_for 'grep -q "error (question" "$H/run/answer.log" 2>/dev/null' && kill -0 "$(cat "$H/run/answer.pid")" 2>/dev/null \
  && pass "answer.py: server down -> error logged, still running" || { fail "answer.py: server down"; cat "$H/run/answer.log"; }
reply "Within the agreed plan."
start_stub
echo "[12:01:10] THEM: Sam, and the budget?" >> "$Q"
wait_for '[ "$(answers)" = 4 ]' && tail -n 3 "$SESSION/answers.md" | grep -q "Within the agreed plan." \
  && pass "answer.py: answers again when the server is back" || fail "answer.py: recovery"

# 6. A new meeting with earlier questions: the backlog is skipped, not answered late.
S2="$H/sessions/2026-01-01-1300"; mkdir -p "$S2"; : > "$S2/transcript.txt"
printf '[13:00:00] THEM: Sam, old one?\n[13:00:05] THEM: Sam, old two?\n' > "$S2/questions.log"
echo "$S2/transcript.txt" > "$H/sessions/LATEST"
wait_for '[ "$(cat "$S2/.answer_offset" 2>/dev/null)" = 2 ]' && sleep 1 && [ ! -f "$S2/answers.md" ] \
  && pass "answer.py: follows the new meeting, skips its backlog" || fail "answer.py: new meeting"
echo "$H/sessions/deleted/transcript.txt" > "$H/sessions/LATEST"
sleep 1.5
kill -0 "$(cat "$H/run/answer.pid")" 2>/dev/null && pass "answer.py: survives a missing session folder" || fail "answer.py: missing folder"
echo "$T" > "$H/sessions/LATEST"

# 7. stop.sh stops it.
APID=$(cat "$H/run/answer.pid")
bash "$S/stop.sh" > /dev/null
sleep 0.5
! kill -0 "$APID" 2>/dev/null && [ ! -f "$H/run/answer.pid" ] && pass "stop.sh: answerer stopped" || fail "stop.sh: answerer"

# 8. --test with the other providers (same stand-in server), and keys never logged.
reply "Here is where it stands."
OUT=$(ONCUE_PROVIDER=openai OPENAI_BASE_URL="http://127.0.0.1:$PORT/v1" OPENAI_API_KEY=sk-test-SECRET0123456789 \
      ONCUE_LLM_MODEL=test-model python3 "$S/answer.py" --test 2>&1)
python3 - "$REQS" <<'PY' && echo "$OUT" | grep -q "reply: Here is where it stands." \
  && pass "answer.py: openai-compatible request" || { fail "answer.py: openai"; echo "$OUT"; }
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])][-1]
assert r["path"] == "/v1/chat/completions" and r["auth"] == "Bearer sk-test-SECRET0123456789", r
assert r["body"]["model"] == "test-model" and r["body"]["messages"][0]["role"] == "system", r
PY
OUT=$(ONCUE_PROVIDER=anthropic ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT" ANTHROPIC_API_KEY=sk-ant-SECRET0123456789 \
      python3 "$S/answer.py" --test 2>&1)
python3 - "$REQS" <<'PY' && echo "$OUT" | grep -q "reply: Here is where it stands." \
  && pass "answer.py: anthropic request" || { fail "answer.py: anthropic"; echo "$OUT"; }
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])][-1]
assert r["path"] == "/v1/messages" and r["auth"] == "sk-ant-SECRET0123456789" and r["version"] == "2026-10-21", r
b = r["body"]
assert b["model"] == "claude-haiku-5-5" and b["max_tokens"] >= 1024 and isinstance(b["system"], str), b
assert b["output_config"] == {"effort": "low"} and not {"temperature", "top_p", "top_k"} & set(b), b
assert [m["role"] for m in b["messages"]] == ["user"], b
PY
reply "401"
OUT=$(ONCUE_PROVIDER=openai OPENAI_BASE_URL="http://127.0.0.1:$PORT/v1" OPENAI_API_KEY=sk-test-SECRET0123456789 \
      python3 "$S/answer.py" --test 2>&1)
echo "$OUT" | grep -q "HTTP 401" && ! echo "$OUT" | grep -q SECRET && ! grep -q SECRET "$H/run/answer.log" \
  && pass "answer.py: API keys never printed or logged" || { fail "answer.py: key leaked"; echo "$OUT"; }
ONCUE_PROVIDER=nonsense python3 "$S/answer.py" --test > /dev/null 2>&1 && fail "answer.py: unknown provider accepted" \
  || pass "answer.py: unknown provider refused"

[ "$FAIL" = 0 ] || exit 1
