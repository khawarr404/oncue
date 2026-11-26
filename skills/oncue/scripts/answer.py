"""Standalone answerer: suggested answers without a coding agent, from a local model (Ollama) or an API.

Follows questions.log of the current meeting (questions watch.sh found, and quick actions from the
dashboard), asks the model for a short answer, and shows it the way the agent would: in answers.md (the
dashboard) and as a desktop pop-up, through notify.sh. It keeps its own read position (.answer_offset in
the session folder), so next-question.sh still sees every question.

Providers (ONCUE_PROVIDER):
  ollama     default. Runs on this computer; nothing leaves it. ONCUE_OLLAMA_URL (http://127.0.0.1:11434)
  anthropic  ANTHROPIC_API_KEY. Transcript text and your notes are sent to Anthropic.
  openai     OPENAI_API_KEY, OPENAI_BASE_URL (https://api.openai.com/v1, or any OpenAI-compatible endpoint
             such as OpenRouter). Transcript text and your notes are sent to that provider.
ONCUE_LLM_MODEL sets the model, ONCUE_LLM_TIMEOUT the request timeout in seconds (30).

Usage: python3 answer.py           run until stopped (scripts/stop.sh); up.sh --answer starts it detached
       python3 answer.py --test    ask one sample question, print the reply and exit (checks your settings)
Log: $ONCUE_HOME/run/answer.log. Standard library only.
"""
import argparse
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

HOME = Path(os.environ.get("ONCUE_HOME") or Path.home() / "oncue")
SKILL_DIR = Path(__file__).resolve().parent.parent
NOTIFY = SKILL_DIR / "scripts" / "notify.sh"
RUN = HOME / "run"
PID_FILE = RUN / "answer.pid"
LOG_FILE = RUN / "answer.log"

PROVIDER = (os.environ.get("ONCUE_PROVIDER") or "ollama").strip().lower()
DEFAULT_MODELS = {"ollama": "llama3.2", "anthropic": "claude-haiku-5-5", "openai": "gpt-4o-mini"}
MODEL = os.environ.get("ONCUE_LLM_MODEL") or DEFAULT_MODELS.get(PROVIDER, "")
TIMEOUT = float(os.environ.get("ONCUE_LLM_TIMEOUT") or 30)
POLL = 0.5                 # seconds between looks at questions.log
CONTEXT_LINES = 15         # transcript lines sent with a question
RECAP_SECONDS = 300        # a recap covers the last 5 minutes
MAX_NOTES = 6000           # characters kept from each of CONTEXT.md, prep.md and the mode file

LINE = re.compile(r"^\[(\d\d:\d\d:\d\d)\] (ME|THEM): (.*)$")
QLINE = re.compile(r"^\[(\d\d:\d\d:\d\d)\] (THEM|ACTION): (.*)$")
ACTIONS = ("answer", "clarify", "recap", "followup")
ACTION_TITLES = {"clarify": "Clarify", "recap": "Recap", "followup": "Follow-up"}
MODE_NAME = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


class ProviderError(Exception):
    pass


def redact(text):
    """Remove API keys from text before it is logged (some providers echo part of a wrong key)."""
    for var in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY"):
        key = os.environ.get(var)
        if key:
            text = text.replace(key, "***")
    return re.sub(r"\b(sk|key)[-_][A-Za-z0-9*_\-]{6,}", r"\1-***", text)


def log(msg):
    try:
        RUN.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {redact(msg)}\n")
    except OSError:
        pass


def read(path, limit=MAX_NOTES):
    try:
        text = Path(path).read_text(errors="ignore").strip()
    except OSError:
        return ""
    return text if len(text) <= limit else text[:limit] + "\n[...cut]"


def secs(hms):
    h, m, s = (int(x) for x in hms.split(":"))
    return h * 3600 + m * 60 + s


# ---------- model providers ----------

# A local model is reached directly, never through an http_proxy set in the environment.
DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def post_json(url, body, headers, timeout):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", **headers})
    local = urlsplit(url).hostname in ("127.0.0.1", "localhost", "::1")
    try:
        with (DIRECT.open if local else urllib.request.urlopen)(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        detail = e.read()[:300].decode("utf-8", "replace") if e.fp else ""
        raise ProviderError(f"{PROVIDER} HTTP {e.code}: {detail}") from None
    except urllib.error.URLError as e:
        raise ProviderError(f"{PROVIDER} not reachable at {url}: {e.reason}") from None
    except (TimeoutError, OSError) as e:
        raise ProviderError(f"{PROVIDER} request failed: {type(e).__name__}: {e}") from None
    except ValueError:
        raise ProviderError(f"{PROVIDER} sent a reply that is not JSON") from None


def ollama_url():
    url = (os.environ.get("ONCUE_OLLAMA_URL") or "http://127.0.0.1:11434").rstrip("/")
    return url if url.endswith("/api/chat") else url + "/api/chat"


def ask(system, user, max_tokens=250, timeout=None):
    """Send one prompt to the configured provider and return the reply text."""
    timeout = timeout or TIMEOUT
    try:
        if PROVIDER == "ollama":
            body = {"model": MODEL, "stream": False, "keep_alive": "30m",
                    "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
                    # Ollama's default context is small; without this a long cheat sheet is silently cut.
                    "options": {"temperature": 0.3, "num_ctx": 8192, "num_predict": max_tokens}}
            return post_json(ollama_url(), body, {}, timeout)["message"]["content"]
        if PROVIDER == "anthropic":
            key = os.environ.get("ANTHROPIC_API_KEY")
            if not key:
                raise ProviderError("ANTHROPIC_API_KEY is not set")
            base = (os.environ.get("ANTHROPIC_BASE_URL") or "https://api.anthropic.com").rstrip("/")
            # Current models think by default and thinking counts against max_tokens: keep effort low (fast) and
            # leave room so the short answer is not cut off. No sampling parameters (rejected by current models).
            body = {"model": MODEL, "max_tokens": max(2048, max_tokens), "system": system,
                    "messages": [{"role": "user", "content": user}]}
            if not re.match(r"claude-(3|haiku-4|sonnet-4-5|opus-4-[01])", MODEL):
                body["output_config"] = {"effort": "low"}
            r = post_json(base + "/v1/messages", body, {"x-api-key": key, "anthropic-version": "2026-10-21"}, timeout)
            text = "".join(b.get("text", "") for b in r["content"] if b.get("type") == "text")
            if not text.strip():
                raise ProviderError(f"anthropic returned no text (stop_reason {r.get('stop_reason')})")
            return text
        if PROVIDER == "openai":
            key = os.environ.get("OPENAI_API_KEY")
            base = (os.environ.get("OPENAI_BASE_URL") or "https://api.openai.com/v1").rstrip("/")
            # No token limit field: endpoints disagree on its name (max_tokens / max_completion_tokens).
            body = {"model": MODEL, "messages": [{"role": "system", "content": system},
                                                 {"role": "user", "content": user}]}
            headers = {"Authorization": f"Bearer {key}"} if key else {}
            return post_json(base + "/chat/completions", body, headers, timeout)["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise ProviderError(f"{PROVIDER} reply had an unexpected shape") from None
    raise ProviderError(f"unknown ONCUE_PROVIDER {PROVIDER!r} (use ollama, anthropic or openai)")


# ---------- prompts ----------

def mode_file():
    try:
        name = (HOME / "mode.txt").read_text().strip()
    except OSError:
        name = ""
    if not MODE_NAME.match(name):
        name = "meeting"
    for path in (HOME / "modes" / f"{name}.md", SKILL_DIR / "modes" / f"{name}.md"):
        if path.exists():
            return path
    return SKILL_DIR / "modes" / "meeting.md"


def system_prompt():
    name = read(HOME / "name.txt", 200).splitlines()
    who = f"The user is {name[0].strip()}. " if name and name[0].strip() else ""
    parts = [
        "You help the user live during a call. " + who +
        "In the transcript, ME is the user and THEM is anyone else on the call; it cannot tell people apart "
        "and has speech-to-text mistakes, so read through them.\n"
        "Write only what the user can say or use right now: short, plain spoken language, no preamble, no "
        "headings, no quotes around it.\n"
        "Use only facts from the notes below and the transcript. Never invent numbers, names, dates, "
        "experience or facts. If the notes do not cover it, give an honest holding line such as "
        "\"Good question, I'll check and come back to you today.\"",
        "## Mode for this call\n" + read(mode_file()),
    ]
    context = read(HOME / "CONTEXT.md")
    if context:
        parts.append("## The user's notes (CONTEXT.md)\n" + context)
    prep = read(HOME / "prep.md")
    if prep:
        parts.append("## Prep for this call (prep.md)\n" + prep)
    return "\n\n".join(parts)


def transcript(path, recap=False):
    """Recent ME/THEM lines: the last few for a question, the last 5 minutes for a recap."""
    lines = []
    for raw in read(path, 10**7).splitlines():
        m = LINE.match(raw)
        if m:
            lines.append((m[1], raw))
    if recap and lines:
        end = secs(lines[-1][0])
        lines = [x for x in lines if (end - secs(x[0])) % 86400 <= RECAP_SECONDS][-150:]
    else:
        lines = lines[-CONTEXT_LINES:]
    return "\n".join(raw for _, raw in lines) or "(nothing transcribed yet)"


def user_prompt(kind, transcript_path, text=""):
    recent = transcript(transcript_path, recap=(kind == "recap"))
    head = ("Transcript of the last 5 minutes:\n" if kind == "recap" else "Recent transcript:\n") + recent + "\n\n"
    if kind == "question":
        return head + (
            f"New line from THEM: \"{text}\"\n\n"
            "If this is not a real question or request for the user (small talk, rhetorical, meant for someone "
            "else, or already answered), reply with exactly: SKIP\n"
            "Otherwise reply with only the suggested answer, as the mode says (usually one or two short sentences).")
    if kind == "answer":
        return head + (
            "The user asked for help: find the latest question or request THEM put to the user (it may be a few "
            "lines back) and suggest an answer, as the mode says. Reply in exactly two lines:\n"
            "Q: <their question, at most 12 words>\nSAY: <the answer>")
    if kind == "clarify":
        return head + (
            "In one line, say in plain words what THEM just asked or said and what they probably want from the "
            "user. Start with \"They're asking\". Reply with only that line.")
    if kind == "recap":
        return head + (
            "Summarise this part of the call in 3 to 5 short bullets, each starting with \"- \". Include decisions, "
            "actions and open questions if there were any. Reply with only the bullets.")
    return head + (
        "Suggest 1 or 2 good, short questions the user could ask THEM now, based on the conversation and the "
        "prep notes. One per line, each starting with \"- \". Reply with only the questions.")


def clean(text):
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S).strip().strip('"').strip()
    text = re.sub(r"^(suggested answer|answer|say)\s*:\s*", "", text, flags=re.I)
    return "\n".join(line.rstrip() for line in text.splitlines() if line.strip()).strip()


def is_skip(reply):
    return re.match(r"^\W*skip\b", reply, re.I) is not None


def split_answer(reply, fallback_q):
    """For the Answer action: the model replies "Q: ...\nSAY: ..."."""
    q = re.search(r"^\W*Q\s*:\s*(.+)$", reply, re.M | re.I)
    say = re.search(r"^\W*SAY\s*:\s*(.+)", reply, re.M | re.I | re.S)
    if say:
        return (q[1].strip() if q else fallback_q), say[1].strip()
    body = "\n".join(line for line in reply.splitlines() if not re.match(r"^\W*Q\s*:", line, re.I)).strip()
    return (q[1].strip() if q else fallback_q), body or reply


def short(text, n=140):
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def notify(question, answer):
    subprocess.run(["bash", str(NOTIFY), question, answer], timeout=20, check=False,
                   env={**os.environ, "ONCUE_HOME": str(HOME)}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def last_them(transcript_path):
    for raw in reversed(read(transcript_path, 10**7).splitlines()):
        m = LINE.match(raw)
        if m and m[2] == "THEM":
            return short(m[3], 90)
    return "Answer"


def handle(line, transcript_path):
    """Answer one questions.log line: "[t] THEM: question" or "[t] ACTION: recap"."""
    m = QLINE.match(line)
    if not m:
        return
    t, who, text = m[1], m[2], m[3].strip()
    kind = "question" if who == "THEM" else text.lower()
    if kind not in ACTIONS and kind != "question":
        log(f"ignored unknown action {text!r}")
        return
    started = time.monotonic()
    try:
        reply = clean(ask(system_prompt(), user_prompt(kind, transcript_path, text),
                          max_tokens=400 if kind in ("recap", "followup") else 250))
    except ProviderError as e:
        log(f"error ({kind} at {t}): {e}")
        return
    if not reply:
        log(f"empty reply ({kind} at {t})")
        return
    if kind == "question" and is_skip(reply):
        log(f"skipped (not for the user): {short(text, 80)}")
        return
    if kind == "question":
        question, answer = short(text), reply
    elif kind == "answer":
        question, answer = split_answer(reply, last_them(transcript_path))
    else:
        question, answer = ACTION_TITLES[kind], reply
    notify(question, answer)
    log(f"answered {kind} at {t} in {time.monotonic() - started:.1f}s")


# ---------- main loop ----------

def complete_lines(path):
    try:
        data = path.read_bytes()
    except OSError:
        return []
    return data.decode("utf-8", "replace").split("\n")[:-1]  # the last piece is unfinished (or empty)


def read_offset(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def pid_alive(path):
    try:
        os.kill(int(path.read_text().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def shutdown(*_):
    try:
        if PID_FILE.read_text().strip() == str(os.getpid()):
            PID_FILE.unlink()
    except OSError:
        pass
    sys.exit(0)


def warm_up():
    """Load the local model now, so the first real question does not wait for it."""
    try:
        ask("Reply with OK.", "OK?", max_tokens=1, timeout=180)
    except ProviderError as e:
        log(f"warm-up: {e}")


def run():
    if pid_alive(PID_FILE):
        print("answerer already running")
        return
    RUN.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, shutdown)
    log(f"started: provider {PROVIDER}, model {MODEL}")
    print(f"answering with {PROVIDER} ({MODEL}); log: {LOG_FILE}", flush=True)
    if PROVIDER == "ollama":
        threading.Thread(target=warm_up, daemon=True).start()
    state, last_error = {"session": None, "offset": 0, "size": -1}, ""
    while True:
        try:
            poll(state)
        except Exception as e:  # a missing folder or a full disk must not end the answerer
            msg = f"error: {type(e).__name__}: {e}"
            if msg != last_error:  # log a repeating problem once, not twice a second
                log(msg)
            last_error = msg
        time.sleep(POLL)


def save_offset(path, offset):
    try:
        path.write_text(f"{offset}\n")
    except OSError as e:
        log(f"cannot save read position: {e}")


def poll(state):
    """One look at the current meeting's questions.log; answers any new complete lines."""
    session, offset, size = state["session"], state["offset"], state["size"]
    try:
        pointer = (HOME / "sessions" / "LATEST").read_text().strip()
    except OSError:
        pointer = ""
    if pointer:
        f = Path(pointer)
        qlog, offset_file = f.parent / "questions.log", f.parent / ".answer_offset"
        if f.parent != session:
            session, size = f.parent, -1
            offset = read_offset(offset_file)
            if offset is None:
                # First look at this meeting: questions asked before the answerer started are stale.
                offset = len(complete_lines(qlog))
                save_offset(offset_file, offset)
                if offset:
                    log(f"skipped {offset} earlier lines in {session.name}")
            state.update(session=session, offset=offset, size=size)
        try:
            new_size = qlog.stat().st_size
        except OSError:
            new_size = 0
        if new_size != size:
            size = new_size
            lines = complete_lines(qlog)
            offset = min(offset, len(lines))
            while offset < len(lines):
                line = lines[offset]
                offset += 1
                # Move on before answering: a failed or slow answer is never repeated (it would be stale).
                state["offset"] = offset
                save_offset(offset_file, offset)
                try:
                    handle(line, f)
                except Exception as e:  # never let one bad answer stop the loop
                    log(f"error: {type(e).__name__}: {e}")
    state.update(session=session, offset=offset, size=size)


def test():
    """One sample question through the configured provider, printed instead of shown."""
    print(f"provider: {PROVIDER}, model: {MODEL}, mode: {mode_file().stem}")
    sample = HOME / "run" / "answer-test.txt"
    sample.parent.mkdir(parents=True, exist_ok=True)
    sample.write_text("[10:00:00] ME: that's the plan for this week\n"
                      "[10:00:05] THEM: thanks. Can you give us a quick update on where your project stands?\n")
    try:
        reply = clean(ask(system_prompt(), user_prompt("question", sample,
                                                       "thanks. Can you give us a quick update on where your project stands?")))
    except ProviderError as e:
        print(f"error: {redact(str(e))}")
        log(f"test: {e}")
        return 1
    finally:
        sample.unlink(missing_ok=True)
    print(f"reply: {reply}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Suggest answers in the current meeting with your own model.")
    ap.add_argument("--test", action="store_true", help="ask one sample question, print the reply and exit")
    args = ap.parse_args()
    if PROVIDER not in DEFAULT_MODELS:
        log(f"unknown ONCUE_PROVIDER {PROVIDER!r}")
        sys.exit(f"unknown ONCUE_PROVIDER {PROVIDER!r}: use ollama, anthropic or openai")
    if args.test:
        sys.exit(test())
    try:
        run()
    except KeyboardInterrupt:
        shutdown()
