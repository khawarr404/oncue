#!/bin/bash
# One-time setup: checks the audio tools, creates a Python env with faster-whisper, downloads the speech
# model, and creates the user's data folder (cheat sheet, word list). Safe to run again.
set -e
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${ONCUE_HOME:-$HOME/oncue}"
# small.en won the benchmark in references/platforms.md (fastest, as accurate as the large models here).
MODEL="${ONCUE_MODEL:-small.en}"
mkdir -p "$HOME_DIR/sessions"

command -v pw-record >/dev/null || { echo "MISSING: pw-record (PipeWire). This version supports Linux with PipeWire only. See references/platforms.md"; exit 1; }
command -v notify-send >/dev/null || echo "NOTE: notify-send not found; answers will show in the chat only."

if [ ! -x "$HOME_DIR/.venv/bin/python" ]; then
  if command -v uv >/dev/null; then
    uv venv --python 3.12 "$HOME_DIR/.venv" -q
    uv pip install --python "$HOME_DIR/.venv/bin/python" -q faster-whisper numpy
  else
    python3 -m venv "$HOME_DIR/.venv"
    "$HOME_DIR/.venv/bin/pip" install -q faster-whisper numpy
  fi
fi
"$HOME_DIR/.venv/bin/python" -c "from faster_whisper import WhisperModel; WhisperModel('$MODEL', device='cpu', compute_type='int8'); print('model ready: $MODEL')"

[ -f "$HOME_DIR/CONTEXT.md" ] || cp "$SKILL_DIR/assets/CONTEXT.template.md" "$HOME_DIR/CONTEXT.md"
[ -f "$HOME_DIR/vocab.txt" ] || echo "Add names, product names and jargon here, comma separated." > "$HOME_DIR/vocab.txt"
echo "ready: $HOME_DIR"
