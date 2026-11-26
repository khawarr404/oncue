"""Floating answer window: a small always-on-top window that shows the latest suggested answer, so you can read
it while looking at the call.

Reads the dashboard's GET /api/state every 1.5 s (dashboard.py must be running; the window says so and keeps
retrying if not). The buttons post to the dashboard like its own page does, with the token the dashboard
writes to $ONCUE_HOME/run/dashboard.token (re-read when the dashboard restarts).

Keys (as on the dashboard): A answer, K clarify, R recap, F follow-up, Y copy the answer, C compact (answer
only), + / - opacity. Position, size, opacity and compact are kept in $ONCUE_HOME/float.json.
Standard library only (tkinter).

Usage: python3 float.py [--port 8765]   (or ONCUE_PORT)
       python3 float.py --check          print what the window would show, then exit (no display needed)
"""
import argparse
import json
import os
import queue
import re
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path(os.environ.get("ONCUE_HOME") or Path.home() / "oncue")
RUN = HOME / "run"
PID_FILE = RUN / "float.pid"
TOKEN_FILE = RUN / "dashboard.token"
SETTINGS_FILE = HOME / "float.json"
POLL_SECONDS = 1.5
NAMES = {"answer": "Answer", "clarify": "Clarify", "recap": "Recap", "followup": "Follow-up"}
KEYS = {"a": "answer", "k": "clarify", "r": "recap", "f": "followup"}
DEFAULTS = {"geometry": "420x220", "alpha": 0.95, "compact": False}
ALPHA_MIN, ALPHA_MAX, ALPHA_STEP = 0.3, 1.0, 0.05
GEOMETRY = re.compile(r"^(\d{2,5})x(\d{2,5})(?:[+-]-?\d{1,5}[+-]-?\d{1,5})?$")
MIN_W, MIN_H = 260, 120

# Dashboard colours
BG, PANEL, PANEL2, LINE = "#0b0d12", "#12151c", "#171b24", "#232836"
INK, INK2, MUTED = "#eceef3", "#b9bfcc", "#7d8597"
ACCENT, OK, WARN, WARN_BG, BAD = "#8ea2ff", "#3fd68a", "#f2c46b", "#221d12", "#e5737a"
FLASH = (ACCENT, ACCENT, ACCENT, "#7a8ad6", "#6170ad", "#4a5583", "#353d5c", LINE)  # border fade, 250 ms steps


# ---------- pure parts (tested without a display) ----------

def clamp_alpha(value):
    try:
        a = float(value)
    except (TypeError, ValueError):
        return DEFAULTS["alpha"]
    if a != a:  # NaN
        return DEFAULTS["alpha"]
    return round(min(ALPHA_MAX, max(ALPHA_MIN, a)), 2)


def valid_geometry(g):
    """True for a Tk geometry like 420x220 or 420x220+100+50 that is not smaller than the minimum size."""
    m = GEOMETRY.match(g) if isinstance(g, str) else None
    return bool(m) and int(m[1]) >= MIN_W and int(m[2]) >= MIN_H


def load_settings(path=SETTINGS_FILE):
    """Saved position, size, opacity and compact mode; defaults for anything missing or broken."""
    s = dict(DEFAULTS)
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return s
    if not isinstance(data, dict):
        return s
    if valid_geometry(data.get("geometry")):
        s["geometry"] = data["geometry"]
    a = data.get("alpha")
    if isinstance(a, (int, float)) and not isinstance(a, bool):
        s["alpha"] = clamp_alpha(a)
    if isinstance(data.get("compact"), bool):
        s["compact"] = data["compact"]
    return s


def save_settings(settings, path=SETTINGS_FILE):
    """Write settings (only the known keys); False if the folder is not writable."""
    path = Path(path)
    data = {k: settings.get(k, v) for k, v in DEFAULTS.items()}
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.{os.getpid()}")
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def read_token(path=TOKEN_FILE):
    try:
        return Path(path).read_text().strip() or None
    except OSError:
        return None


def view(state, port, online=True):
    """What the window shows for a /api/state reply. state may be the last good one while offline, or None."""
    s = state if isinstance(state, dict) else {}
    live = bool(s.get("live")) and online
    mode = s.get("mode") or "meeting"
    if not online:
        status, tone = f"Dashboard offline (127.0.0.1:{port}) · retrying", "bad"
    elif s.get("live"):
        status, tone = f"Listening · {mode} mode", "live"
    elif s.get("session"):
        status, tone = f"Stopped · {mode} mode", "idle"
    else:
        status, tone = f"Not started · {mode} mode", "idle"

    pending = pending_text = None
    p = s.get("pending") if online else None
    if isinstance(p, dict):
        if p.get("who") == "ACTION":
            pending = f"{NAMES.get(p.get('text'), p.get('text'))} asked… coming"
            pending_text = p.get("t", "")
        else:
            pending = "Question heard… answer coming"
            pending_text = f"{p.get('t', '')} · {p.get('text', '')}"

    answers = s.get("answers") or []
    if answers:
        a = answers[-1]
        question = f"{a.get('time', '')} · {a.get('q', '')}"
        answer, empty = a.get("say", ""), False
        key = f"{a.get('time')}|{a.get('q')}|{a.get('say')}"
    else:
        question, empty, key = "", True, ""
        if state is None:
            answer = "The dashboard is not running. Start oncue (up.sh) or dashboard.py; this window keeps trying."
        elif live:
            answer = "Waiting for a question…"
        else:
            answer = "No answers yet"
    return {"online": online, "live": live, "status": status, "tone": tone, "mode": mode,
            "modes": list(s.get("modes") or [mode]), "pending": pending, "pending_text": pending_text,
            "question": question, "answer": answer, "empty": empty, "key": key}


class Client:
    """Talks to the dashboard on 127.0.0.1 (never through a proxy). POSTs carry the token from
    run/dashboard.token, re-read once when the dashboard answers 403 (it was restarted: new token)."""

    def __init__(self, port, token_file=TOKEN_FILE, timeout=2.0):
        self.base = f"http://127.0.0.1:{port}"
        self.token_file = token_file
        self.timeout = timeout
        self.token = read_token(token_file)
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def get_state(self):
        with self.opener.open(self.base + "/api/state", timeout=self.timeout) as r:
            return json.load(r)

    def post(self, path, body):
        """Returns (ok, reply dict or error text)."""
        for attempt in (0, 1):
            if attempt or not self.token:
                self.token = read_token(self.token_file)
            if not self.token:
                return False, "No dashboard token: is the dashboard running?"
            req = urllib.request.Request(self.base + path, data=json.dumps(body).encode(), method="POST",
                                         headers={"Content-Type": "application/json", "X-Oncue-Token": self.token})
            try:
                with self.opener.open(req, timeout=self.timeout) as r:
                    return True, json.load(r)
            except urllib.error.HTTPError as e:
                if e.code == 403 and attempt == 0:
                    continue
                try:
                    msg = json.load(e).get("error") or f"Error {e.code}"
                except (ValueError, AttributeError):
                    msg = f"Error {e.code}"
                return False, msg
            except (urllib.error.URLError, OSError, ValueError):
                return False, "Dashboard offline"
        return False, "Dashboard refused the token"


def pid_alive(path):
    try:
        os.kill(int(Path(path).read_text().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def check(port):
    """--check: fetch the state once and print what the window would show."""
    client = Client(port)
    try:
        state, online = client.get_state(), True
    except (urllib.error.URLError, OSError, ValueError):
        state, online = None, False
    v = view(state, port, online)
    print(f"status: {v['status']}")
    if v["pending"]:
        print(f"pending: {v['pending']} {v['pending_text']}".rstrip())
    if v["question"]:
        print(f"question: {v['question']}")
    print(f"answer: {v['answer']}")
    print(f"token: {'found' if read_token() else 'missing'}")
    return 0


# ---------- the window ----------

class FloatWindow:
    def __init__(self, tk, port):
        self.tk, self.port = tk, port
        self.client = Client(port)
        self.settings = load_settings()
        self.inbox = queue.Queue()
        self.stop, self.wake = threading.Event(), threading.Event()
        self.last_state, self.answer_key, self.shown_answer = None, None, None
        self.mode_chosen_at, self.modes, self.msg_job, self.save_job, self.flash_job = 0.0, None, None, None, None
        self.view = view(None, port, online=False)

        root = self.root = tk.Tk(className="oncue-float")
        root.title("oncue")
        root.configure(bg=BG)
        root.minsize(MIN_W, MIN_H)
        root.geometry(self.settings["geometry"])
        root.attributes("-topmost", True)
        self.set_alpha(self.settings["alpha"], save=False)
        root.protocol("WM_DELETE_WINDOW", self.close)

        import tkinter.font as tkfont
        family = tkfont.nametofont("TkDefaultFont").actual()["family"]
        small, self.big = (family, 10), (family, 16, "bold")
        root.columnconfigure(0, weight=1)
        root.rowconfigure(3, weight=1)

        # Row 0: status (and short messages such as "Copied"), mode menu, opacity
        top = self.top = tk.Frame(root, bg=BG)
        top.grid(row=0, column=0, sticky="ew", padx=10, pady=(8, 2))
        self.dot = tk.Label(top, text="●", bg=BG, fg=MUTED, font=small)
        self.dot.pack(side="left")
        self.status = tk.Label(top, text="Connecting…", bg=BG, fg=INK2, font=small, anchor="w")
        self.note = ""  # a short message ("Copied", "Recap asked…") shown in the status line for a few seconds
        self.alpha_scale = tk.Scale(top, from_=int(ALPHA_MIN * 100), to=100, orient="horizontal", showvalue=0,
                                    length=56, width=8, sliderlength=12, bd=0, highlightthickness=0, bg=BG,
                                    troughcolor=LINE, activebackground=ACCENT, command=self.on_scale)
        self.alpha_scale.set(int(self.settings["alpha"] * 100))
        self.alpha_scale.pack(side="right", padx=(6, 0))
        tk.Label(top, text="◐", bg=BG, fg=MUTED, font=small).pack(side="right")
        self.mode_var = tk.StringVar(value=self.view["mode"])
        self.mode_menu = tk.OptionMenu(top, self.mode_var, self.view["mode"])
        self.mode_menu.configure(bg=PANEL2, fg=INK, activebackground=LINE, activeforeground=INK, bd=0,
                                 highlightthickness=0, relief="flat", font=small, padx=8, pady=1, indicatoron=0)
        self.mode_menu["menu"].configure(bg=PANEL, fg=INK, activebackground=LINE, activeforeground=INK, font=small)
        self.mode_menu.pack(side="right")
        self.status.pack(side="left", padx=(4, 0), fill="x", expand=True)  # last: the menu and slider keep their room

        # Row 1: the question the answer is for. Row 2: "question heard… answer coming"
        self.qlabel = tk.Label(root, text="", bg=BG, fg=MUTED, font=small, anchor="w", justify="left")
        self.qlabel.grid(row=1, column=0, sticky="ew", padx=12)
        self.pending = tk.Label(root, text="", bg=WARN_BG, fg=WARN, font=small, anchor="w", justify="left",
                                padx=8, pady=3)
        self.pending.grid(row=2, column=0, sticky="ew", padx=10, pady=(4, 0))
        self.pending.grid_remove()

        # Row 3: the answer (selectable, scrolls with the wheel when long)
        self.box = tk.Frame(root, bg=PANEL, highlightthickness=2, highlightbackground=LINE, highlightcolor=LINE)
        self.box.grid(row=3, column=0, sticky="nsew", padx=10, pady=(4, 6))
        self.text = tk.Text(self.box, bg=PANEL, fg=INK, font=self.big, wrap="word", bd=0, highlightthickness=0,
                            padx=10, pady=8, cursor="arrow", insertwidth=0, selectbackground=LINE,
                            selectforeground=INK, height=3, width=20, takefocus=0)
        self.text.pack(fill="both", expand=True)

        # Row 4: quick actions and copy
        self.bar = tk.Frame(root, bg=BG)
        self.bar.grid(row=4, column=0, sticky="ew", padx=10, pady=(0, 8))
        self.buttons = {}
        for name in ("answer", "clarify", "recap", "followup"):
            b = self.button(self.bar, NAMES[name], lambda n=name: self.act(n), small)
            b.pack(side="left", padx=(0, 4))
            self.buttons[name] = b
        self.copy_btn = self.button(self.bar, "Copy", self.copy, small)
        self.copy_btn.pack(side="right")

        root.bind("<KeyPress>", self.on_key)
        root.bind("<Configure>", self.on_configure)
        self.set_compact(self.settings["compact"], save=False)
        self.render()
        threading.Thread(target=self.poll_loop, daemon=True).start()
        root.after(100, self.drain)

    def button(self, parent, text, command, font):
        return self.tk.Button(parent, text=text, command=command, font=font, bg=PANEL2, fg=INK,
                              activebackground=LINE, activeforeground=INK, disabledforeground="#4a5162",
                              relief="flat", bd=0, highlightthickness=0, padx=8, pady=3, takefocus=0)

    # --- background work: the network never blocks the window ---
    def poll_loop(self):
        while not self.stop.is_set():
            try:
                self.inbox.put(("state", self.client.get_state()))
            except (urllib.error.URLError, OSError, ValueError):
                self.inbox.put(("offline", None))
            self.wake.wait(POLL_SECONDS)
            self.wake.clear()

    def post(self, path, body, done):
        def work():
            ok, reply = self.client.post(path, body)
            self.inbox.put(("msg", done if ok else reply))
            self.wake.set()
        threading.Thread(target=work, daemon=True).start()

    def drain(self):
        try:
            while True:
                kind, data = self.inbox.get_nowait()
                if kind == "state":
                    self.last_state = data
                    self.view = view(data, self.port, online=True)
                    self.render()
                elif kind == "offline":
                    self.view = view(self.last_state, self.port, online=False)
                    self.render()
                else:
                    self.say(data)
        except queue.Empty:
            pass
        if not self.stop.is_set():
            self.root.after(100, self.drain)

    # --- drawing ---
    def render(self):
        v = self.view
        self.status.configure(text=self.note or v["status"], fg=INK if self.note else INK2)
        self.dot.configure(fg={"live": OK, "bad": BAD}.get(v["tone"], MUTED))
        modes = tuple(v["modes"])
        if modes != self.modes:
            menu = self.mode_menu["menu"]
            menu.delete(0, "end")
            for m in modes:
                menu.add_command(label=m, command=lambda m=m: self.choose_mode(m))
            self.modes = modes
        if time.monotonic() - self.mode_chosen_at > 3:
            self.mode_var.set(v["mode"])
        self.qlabel.configure(text=v["question"])
        if v["pending"]:
            self.pending.configure(text=f"● {v['pending']}   {v['pending_text']}".rstrip())
            self.pending.grid()
        else:
            self.pending.grid_remove()
        if v["answer"] != self.shown_answer:
            self.text.configure(state="normal")
            self.text.delete("1.0", "end")
            self.text.insert("1.0", v["answer"])
            self.text.configure(state="disabled")
            self.shown_answer = v["answer"]
        # Dimmed while the next answer is on its way, like the dashboard.
        self.text.configure(fg=MUTED if v["empty"] else INK2 if v["pending"] else INK)
        if v["online"]:
            if self.answer_key is not None and v["key"] and v["key"] != self.answer_key:
                self.flash()
            self.answer_key = v["key"]
        for b in self.buttons.values():
            b.configure(state="normal" if v["live"] else "disabled")
        self.copy_btn.configure(state="disabled" if v["empty"] else "normal")

    def flash(self, step=0):
        """A new answer: the border lights up in the accent colour and fades back."""
        if self.flash_job and step == 0:
            self.root.after_cancel(self.flash_job)
        self.box.configure(highlightbackground=FLASH[step], highlightcolor=FLASH[step])
        self.flash_job = self.root.after(250, self.flash, step + 1) if step + 1 < len(FLASH) else None

    def say(self, text):
        self.note = text
        if self.msg_job:
            self.root.after_cancel(self.msg_job)
        self.msg_job = self.root.after(4000, self.clear_note)
        self.render()

    def clear_note(self):
        self.note, self.msg_job = "", None
        self.render()

    # --- user actions ---
    def act(self, name):
        if not self.view["live"]:
            self.say("Not listening")
            return
        self.say(f"{NAMES[name]}…")
        self.post("/api/action", {"action": name}, f"{NAMES[name]} asked…")

    def choose_mode(self, name):
        self.mode_var.set(name)
        self.mode_chosen_at = time.monotonic()
        self.post("/api/mode", {"mode": name}, f"Mode: {name}")

    def copy(self):
        if self.view["empty"]:
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(self.view["answer"])
        self.say("Copied")

    def set_alpha(self, value, save=True):
        a = clamp_alpha(value)
        self.settings["alpha"] = a
        try:
            self.root.attributes("-alpha", a)
        except self.tk.TclError:
            pass
        if save:
            self.schedule_save()
        return a

    def on_scale(self, value):
        self.set_alpha(int(value) / 100)

    def nudge_alpha(self, delta):
        a = self.set_alpha(self.settings["alpha"] + delta)
        self.alpha_scale.set(int(round(a * 100)))
        self.say(f"Opacity {int(round(a * 100))}%")

    def set_compact(self, on, save=True):
        self.settings["compact"] = on
        for w in (self.top, self.qlabel, self.bar):
            w.grid_remove() if on else w.grid()
        if save:
            self.schedule_save()

    def on_key(self, e):
        if e.state & 0x4 or e.state & 0x8:  # Control or Alt held: leave the key alone (NumLock sets other bits)
            return
        k = e.keysym.lower()
        if k in KEYS:
            self.act(KEYS[k])
        elif k == "y":
            self.copy()
        elif k == "c":
            self.set_compact(not self.settings["compact"])
        elif k in ("plus", "equal", "kp_add"):
            self.nudge_alpha(ALPHA_STEP)
        elif k in ("minus", "underscore", "kp_subtract"):
            self.nudge_alpha(-ALPHA_STEP)

    # --- settings and closing ---
    def on_configure(self, e):
        if e.widget is self.root:
            self.qlabel.configure(wraplength=max(100, e.width - 24))
            self.pending.configure(wraplength=max(100, e.width - 40))
            self.schedule_save()

    def schedule_save(self):
        if self.save_job:
            self.root.after_cancel(self.save_job)
        self.save_job = self.root.after(800, self.save)

    def save(self):
        self.save_job = None
        if self.root.winfo_ismapped():  # before the window is shown its geometry is not real yet
            g = self.root.wm_geometry()
            m = re.match(r"^(\d+x\d+)\+0\+0$", g)
            if m and (self.root.winfo_rootx() > 60 or self.root.winfo_rooty() > 120):
                # Seen with XWayland: +0+0 although the window is elsewhere. Keep the size and the last position.
                last = re.match(r"^\d+x\d+(.*)$", self.settings["geometry"])
                g = m[1] + (last[1] if last else "")
            if valid_geometry(g):
                self.settings["geometry"] = g
        save_settings(self.settings)

    def close(self):
        if self.stop.is_set():
            return
        self.save()
        self.stop.set()
        self.wake.set()
        self.root.destroy()


def run_gui(port):
    if not os.environ.get("DISPLAY"):
        print("float: no display ($DISPLAY is not set); the floating window needs a desktop session",
              file=sys.stderr)
        return 1
    try:
        import tkinter as tk
    except ImportError:
        print("float: this python3 has no tkinter (Debian/Ubuntu: sudo apt install python3-tk)", file=sys.stderr)
        return 1
    if pid_alive(PID_FILE):
        print("float: already running")
        return 0
    try:
        win = FloatWindow(tk, port)
    except tk.TclError as e:
        print(f"float: cannot open a window: {e}", file=sys.stderr)
        return 1
    RUN.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    # stop.sh sends SIGTERM: save and close (tkinter's main loop runs Python signal handlers between events).
    signal.signal(signal.SIGTERM, lambda *_: win.root.after(0, win.close))
    signal.signal(signal.SIGINT, lambda *_: win.root.after(0, win.close))
    print(f"float: showing answers from http://127.0.0.1:{port}", flush=True)
    try:
        win.root.mainloop()
    finally:
        try:
            if PID_FILE.read_text().strip() == str(os.getpid()):
                PID_FILE.unlink()
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Small always-on-top window with the latest suggested answer.")
    ap.add_argument("--port", type=int, default=int(os.environ.get("ONCUE_PORT") or 8765))
    ap.add_argument("--check", action="store_true", help="print what the window would show and exit")
    args = ap.parse_args()
    sys.exit(check(args.port) if args.check else run_gui(args.port))
