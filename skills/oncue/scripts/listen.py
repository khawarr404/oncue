"""Live meeting transcript for any call app (Google Meet, Zoom, Teams, ...) on Linux with PipeWire.

Records two streams with pw-record: what the speakers play (other people, labelled THEM) and the
microphone (labelled ME). Cuts speech at pauses, transcribes each piece locally with faster-whisper,
and appends lines like "[10:02:13] THEM: why did you choose this tool?" to
$ONCUE_HOME/sessions/<date-time>/transcript.txt. The path of the newest transcript is written
to sessions/LATEST. Nothing leaves the machine.

Usage: python listen.py [--model small.en] [--no-mic] [--language en]
Env: ONCUE_MODEL, ONCUE_BEAM, ONCUE_THREADS override the defaults.
Writes its process id to $ONCUE_HOME/run/listen.pid while running.
Stop with Ctrl+C or scripts/stop.sh; the transcript stays.
"""
import argparse
import datetime as dt
import json
import os
import queue
import signal
import subprocess
import sys
import threading
from pathlib import Path

import numpy as np
from faster_whisper import WhisperModel

HOME = Path(os.environ.get("ONCUE_HOME") or Path.home() / "oncue")
RATE = 16000
FRAME = RATE // 10            # 100 ms
SILENCE_RMS = 0.006           # below this a frame counts as silence
PAUSE_FRAMES = 7              # 0.7 s of silence ends a piece of speech
MIN_SPEECH = 1.0              # seconds; shorter pieces are ignored
MAX_SPEECH = 20.0             # seconds; longer speech is cut here
# Picked by benchmark on an Intel Core Ultra 7 155H (CPU, int8): see references/platforms.md.
DEFAULT_MODEL = "small.en"
BEAM = int(os.environ.get("ONCUE_BEAM") or 1)
# About the number of performance cores: more threads spill onto efficiency cores and get slower.
THREADS = int(os.environ.get("ONCUE_THREADS") or min(6, os.cpu_count() or 4))
PID_FILE = HOME / "run" / "listen.pid"
RECORDERS = []                # pw-record processes, stopped on exit


def record(label, extra_args, out_q):
    """Read one pw-record stream and put finished speech pieces on the queue."""
    cmd = ["pw-record", *extra_args, "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=dict(os.environ))
    RECORDERS.append(proc)
    buf, quiet, talking = [], 0, False
    while True:
        raw = proc.stdout.read(FRAME * 2)
        if not raw:
            break
        frame = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768
        if np.sqrt(np.mean(frame ** 2)) > SILENCE_RMS:
            talking, quiet = True, 0
        elif talking:
            quiet += 1
        if talking:
            buf.append(frame)
        length = len(buf) * FRAME / RATE
        if talking and (quiet >= PAUSE_FRAMES or length >= MAX_SPEECH):
            if length >= MIN_SPEECH:
                out_q.put((label, dt.datetime.now(), np.concatenate(buf)))
            buf, quiet, talking = [], 0, False


def shutdown(*_):
    """Stop the recorders and remove the pid file (on Ctrl+C, SIGTERM from stop.sh, or normal exit)."""
    for proc in RECORDERS:
        if proc.poll() is None:
            proc.terminate()
    try:
        if PID_FILE.read_text().strip() == str(os.getpid()):
            PID_FILE.unlink()
    except OSError:
        pass
    sys.exit(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.environ.get("ONCUE_MODEL") or DEFAULT_MODEL)
    ap.add_argument("--language", default="en")
    ap.add_argument("--no-mic", action="store_true", help="only transcribe other people")
    args = ap.parse_args()

    vocab_file = HOME / "vocab.txt"
    vocab = vocab_file.read_text().strip() if vocab_file.exists() else ""
    session = HOME / "sessions" / dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    session.mkdir(parents=True, exist_ok=True)
    out = session / "transcript.txt"
    (HOME / "sessions" / "LATEST").write_text(str(out) + "\n")
    # For the dashboard: which model and settings this meeting uses.
    (session / "session.json").write_text(json.dumps({"model": args.model, "beam": BEAM, "mic": not args.no_mic,
                                                       "started": dt.datetime.now().isoformat(timespec="seconds")}))

    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, shutdown)

    model = WhisperModel(args.model, device="cpu", compute_type="int8", cpu_threads=THREADS)
    q = queue.Queue()
    threading.Thread(target=record, args=("THEM", ["-P", "{ stream.capture.sink=true }"], q), daemon=True).start()
    if not args.no_mic:
        threading.Thread(target=record, args=("ME", [], q), daemon=True).start()
    print(f"listening -> {out}", flush=True)

    with open(out, "a", buffering=1) as f:
        while True:
            label, when, audio = q.get()
            # Pass audio as an array: some PyAV versions break faster-whisper's file decoding.
            segs, _ = model.transcribe(audio, beam_size=BEAM, vad_filter=True, language=args.language,
                                       initial_prompt=vocab or None)
            text = " ".join(s.text.strip() for s in segs).strip()
            if text:
                f.write(f"[{when:%H:%M:%S}] {label}: {text}\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        shutdown()
