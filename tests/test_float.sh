#!/bin/bash
# Floating answer window (float.py) and the dashboard token file it uses: token file mode and removal, local
# client POSTs (no Origin) accepted while cross-site browser requests stay refused, float.py's display logic,
# settings and token reload, and --check. Temporary ONCUE_HOME and a random port; no audio needed.
# The window itself is opened only when a desktop session ($DISPLAY), tkinter and xprop exist
# (ONCUE_SKIP_GUI=1 skips it): it checks the window manager reports it as always on top.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/skills/oncue/scripts"
export ONCUE_HOME="$(mktemp -d)"
export ONCUE_NO_POPUP=1
PORT=$((20000 + RANDOM % 20000))
export ONCUE_PORT="$PORT"
URL="http://127.0.0.1:$PORT"
FAIL=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAIL=1; }
cleanup() {
  for p in "$ONCUE_HOME"/run/*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  [ -n "${FAKE:-}" ] && kill "$FAKE" 2>/dev/null
  [ -n "${DASH:-}" ] && kill "$DASH" 2>/dev/null
  [ -n "${FLOAT:-}" ] && kill "$FLOAT" 2>/dev/null
  rm -rf "$ONCUE_HOME"
}
trap cleanup EXIT
wait_for() { for _ in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.25; done; return 1; }

H="$ONCUE_HOME"; SESSION="$H/sessions/2026-01-01-1200"; T="$SESSION/transcript.txt"; TOK="$H/run/dashboard.token"
mkdir -p "$SESSION" "$H/run"; : > "$T"; echo "$T" > "$H/sessions/LATEST"
echo '{"model": "test", "beam": 1, "mic": true}' > "$SESSION/session.json"
sleep 600 & FAKE=$!; echo "$FAKE" > "$H/run/listen.pid"
echo "[12:00:05] THEM: Sam, what is the budget?" >> "$T"
bash "$S/notify.sh" "What is the budget?" "Within the plan we agreed; I'll send the exact figure today."

start_dashboard() {
  python3 "$S/dashboard.py" --port "$PORT" > /dev/null 2>&1 & DASH=$!
  wait_for 'curl -sf "$URL/api/state" > /dev/null && [ -s "$TOK" ]' || fail "dashboard: did not start"
}

# --- dashboard token file ---
start_dashboard
[ "$(stat -c %a "$TOK" 2>/dev/null)" = 600 ] && pass "token file: mode 0600" || fail "token file: mode $(stat -c %a "$TOK" 2>/dev/null)"
TOKEN=$(cat "$TOK")
PAGE_TOKEN=$(curl -s "$URL/" | sed -n 's/.*name="oncue-token" content="\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] && [ "$TOKEN" = "$PAGE_TOKEN" ] && pass "token file: same token as the page" || fail "token file: differs from page"

# post PATH JSON [curl args...]: prints the HTTP status. curl sends Host 127.0.0.1:PORT and no Origin.
post() { local p="$1" d="$2"; shift 2; curl -s -o "$H/post.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$d" "$@" "$URL$p"; }
[ "$(post /api/mode '{"mode":"interview"}' -H "X-Oncue-Token: $TOKEN")" = 200 ] && [ "$(cat "$H/mode.txt")" = interview ] \
  && pass "local client (Host 127.0.0.1, no Origin, token): mode -> 200" || fail "local client: mode"
[ "$(post /api/action '{"action":"recap"}' -H "X-Oncue-Token: $TOKEN")" = 200 ] && grep -q "ACTION: recap" "$T" \
  && pass "local client: action -> 200" || fail "local client: action"
[ "$(post /api/mode '{"mode":"sales"}' -H "X-Oncue-Token: $TOKEN" -H 'Origin: https://attacker.example')" = 403 ] \
  && pass "browser: foreign Origin -> 403 (even with the token)" || fail "browser: foreign Origin"
[ "$(post /api/mode '{"mode":"sales"}' -H "X-Oncue-Token: $TOKEN" -H 'Sec-Fetch-Site: cross-site')" = 403 ] \
  && pass "browser: Sec-Fetch-Site cross-site -> 403" || fail "browser: cross-site"
[ "$(post /api/mode '{"mode":"sales"}' -H "X-Oncue-Token: $TOKEN" -H "Host: attacker.example:$PORT")" = 403 ] \
  && pass "other host name -> 403" || fail "other host name"
[ "$(post /api/mode '{"mode":"sales"}')" = 403 ] && pass "no token -> 403" || fail "no token"
[ "$(post /api/mode '{"mode":"meeting"}' -H "X-Oncue-Token: $TOKEN" -H "Origin: $URL" -H 'Sec-Fetch-Site: same-origin')" = 200 ] \
  && pass "dashboard page's own request -> 200" || fail "dashboard page's own request"
[ "$(cat "$H/mode.txt")" = meeting ] || fail "mode.txt changed by a refused request"

# --- float.py logic, no display needed ---
python3 - "$S/float.py" "$H" "$PORT" <<'PY' && pass "float.py: view, settings, token, client" || fail "float.py: logic"
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("oncue_float", sys.argv[1])
f = importlib.util.module_from_spec(spec); spec.loader.exec_module(f)
home, port = sys.argv[2], int(sys.argv[3])
assert "tkinter" not in sys.modules, "tkinter must load only for the window"

# view(): offline without any state, offline keeping the last answer, stopped, pending question and action
v = f.view(None, port, online=False)
assert v["status"].startswith("Dashboard offline") and str(port) in v["status"] and v["tone"] == "bad", v
assert v["empty"] and "not running" in v["answer"] and not v["live"], v
st = {"live": True, "session": "s", "mode": "interview", "modes": ["meeting", "interview"],
      "answers": [{"time": "10:00:00", "q": "Budget?", "say": "Within plan."}], "pending": None}
v = f.view(st, port)
assert v["status"] == "Listening · interview mode" and v["tone"] == "live" and v["live"], v
assert v["answer"] == "Within plan." and v["question"] == "10:00:00 · Budget?" and not v["empty"], v
assert v["key"] and v["pending"] is None and v["modes"] == ["meeting", "interview"], v
off = f.view(st, port, online=False)
assert off["answer"] == "Within plan." and not off["live"] and off["status"].startswith("Dashboard offline"), off
v = f.view(dict(st, pending={"t": "10:01:00", "who": "THEM", "text": "And the date?"}), port)
assert v["pending"] == "Question heard… answer coming" and v["pending_text"] == "10:01:00 · And the date?", v
v = f.view(dict(st, pending={"t": "10:02:00", "who": "ACTION", "text": "recap"}), port)
assert v["pending"] == "Recap asked… coming", v
v = f.view({"live": False, "session": "s", "mode": "meeting", "answers": []}, port)
assert v["status"] == "Stopped · meeting mode" and v["answer"] == "No answers yet" and v["empty"], v
v = f.view({"live": True, "session": "s", "answers": []}, port)
assert v["answer"] == "Waiting for a question…" and v["mode"] == "meeting", v
assert f.view({"live": False, "session": "", "answers": []}, port)["status"].startswith("Not started"), "not started"

# settings: defaults when missing or broken, clamped, round trip
p = os.path.join(home, "float-test.json")
assert f.load_settings(p) == f.DEFAULTS
open(p, "w").write("{broken")
assert f.load_settings(p) == f.DEFAULTS
open(p, "w").write(json.dumps({"geometry": "10x10+0+0", "alpha": 5, "compact": "yes"}))
s = f.load_settings(p)
assert s["geometry"] == "420x220" and s["alpha"] == 1.0 and s["compact"] is False, s
open(p, "w").write(json.dumps({"alpha": 0.01}))
assert f.load_settings(p)["alpha"] == 0.3
want = {"geometry": "500x260+40+-8", "alpha": 0.8, "compact": True}
assert f.save_settings(dict(want, extra=1), p) and f.load_settings(p) == want
assert set(json.load(open(p))) == {"geometry", "alpha", "compact"}
assert f.clamp_alpha("x") == f.DEFAULTS["alpha"] and f.clamp_alpha(float("nan")) == f.DEFAULTS["alpha"]

# token: read from run/dashboard.token; a stale one is re-read after a 403
tok = os.path.join(home, "run", "dashboard.token")
assert f.read_token(tok) == open(tok).read().strip()
assert f.read_token(os.path.join(home, "nope")) is None
c = f.Client(port, token_file=tok)
c.token = "stale-token-from-an-earlier-dashboard"
ok, reply = c.post("/api/mode", {"mode": "sales"})
assert ok and reply.get("mode") == "sales" and c.token == f.read_token(tok), (ok, reply)
assert open(os.path.join(home, "mode.txt")).read().strip() == "sales"
ok, reply = c.post("/api/mode", {"mode": "../x"})
assert not ok and reply == "Unknown mode", reply
assert c.get_state()["mode"] == "sales"
bad = f.Client(port, token_file=os.path.join(home, "nope"))
ok, reply = bad.post("/api/mode", {"mode": "meeting"})
assert not ok and "token" in reply, reply
PY

# --- float.py --check ---
OUT=$(python3 "$S/float.py" --check); CODE=$?
[ "$CODE" = 0 ] && echo "$OUT" | grep -q '^status: Listening · sales mode$' \
  && echo "$OUT" | grep -q "^answer: Within the plan we agreed" && echo "$OUT" | grep -q '^token: found$' \
  && pass "float.py --check: shows the latest answer" || { fail "float.py --check"; echo "$OUT"; }

# --- dashboard restart: token removed on exit, new token, client re-reads it ---
OLD="$TOKEN"
kill "$DASH"; wait "$DASH" 2>/dev/null
[ ! -e "$TOK" ] && pass "token file: removed when the dashboard stops (SIGTERM)" || fail "token file: left after exit"
OUT=$(python3 "$S/float.py" --check); CODE=$?
[ "$CODE" = 0 ] && echo "$OUT" | grep -q '^status: Dashboard offline' && pass "float.py --check: dashboard offline" \
  || { fail "float.py --check offline"; echo "$OUT"; }
start_dashboard
[ "$(cat "$TOK")" != "$OLD" ] && pass "token file: new token after restart" || fail "token file: same token after restart"
python3 - "$S/float.py" "$TOK" "$PORT" "$OLD" <<'PY' && pass "float.py: re-reads the token after a restart (403)" || fail "float.py: token reload"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("oncue_float", sys.argv[1])
f = importlib.util.module_from_spec(spec); spec.loader.exec_module(f)
c = f.Client(int(sys.argv[3]), token_file=sys.argv[2])
c.token = sys.argv[4]  # the token from before the restart
ok, reply = c.post("/api/action", {"action": "clarify"})
assert ok and c.token != sys.argv[4], (ok, reply)
PY

# --- the window (needs a desktop session) ---
if [ -n "${ONCUE_SKIP_GUI:-}" ] || [ -z "${DISPLAY:-}" ] || ! command -v xprop > /dev/null \
    || ! python3 -c "import tkinter" 2>/dev/null; then
  echo "SKIP float window test (needs \$DISPLAY, tkinter and xprop)"
else
  # Tk sets no _NET_WM_PID: take the window with class oncue-float that was not there before this start
  # (so a floating window you already have open is never the one checked).
  clients() { xprop -root _NET_CLIENT_LIST | sed 's/^[^#]*# //; s/,/ /g'; }
  BEFORE=" $(clients) "
  python3 "$S/float.py" > "$H/float.out" 2>&1 & FLOAT=$!
  wait_for '[ -f "$H/run/float.pid" ]' || fail "float: no pid file"
  sleep 2
  WIN=""
  for id in $(clients); do
    case "$BEFORE" in *" $id "*) continue ;; esac
    xprop -id "$id" WM_CLASS 2>/dev/null | grep -q '"oncue-float"' && { WIN=$id; break; }
  done
  [ -n "$WIN" ] && pass "float: window listed by the window manager" || { fail "float: window not found"; cat "$H/float.out"; }
  if [ -n "$WIN" ]; then
    xprop -id "$WIN" _NET_WM_STATE | grep -q _NET_WM_STATE_ABOVE \
      && pass "float: always on top (_NET_WM_STATE_ABOVE)" || { fail "float: not on top"; xprop -id "$WIN" _NET_WM_STATE; }
  fi
  bash "$S/stop.sh" > /dev/null
  wait_for '! kill -0 "$FLOAT" 2>/dev/null' 20 && [ ! -f "$H/run/float.pid" ] && pass "stop.sh: floating window closed" \
    || fail "stop.sh: floating window still running"
  python3 -c "import json,sys; s=json.load(open(sys.argv[1])); assert s['geometry'].startswith('420x220'), s" "$H/float.json" \
    && pass "float: settings saved on close" || { fail "float: settings not saved"; cat "$H/float.json"; }
  FLOAT=""
fi

[ "$FAIL" = 0 ] || exit 1
