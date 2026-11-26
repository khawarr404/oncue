# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Most wanted

- **macOS audio capture** (BlackHole + `ffmpeg -f avfoundation`), see
  [platforms.md](skills/oncue/references/platforms.md).
- **Windows audio capture** (WASAPI loopback via `soundcard` or `pyaudiowpatch`).
- **PulseAudio-only Linux** (`parec` on the sink monitor).
- Reports from Cursor, Codex, Gemini CLI, Copilot and Windsurf: does the `next-question.sh` loop hold up
  for a full meeting? What breaks?
- Speaker separation (who said what) that still runs locally.

## Ground rules

- **Audio stays local.** Speech is transcribed on the machine and transcripts are stored locally. A change
  that sends audio or meeting content to any other network service must be opt-in and clearly labelled.
- Keep dependencies small: the scripts use bash, coreutils, awk, Python's standard library, `numpy` and
  `faster-whisper`.
- Never commit real transcripts, cheat sheets or names from real meetings, including in tests and issues.
- Speech model changes need a benchmark like the one in `platforms.md` (accuracy and seconds per clip).

## Before you open a pull request

```bash
bash tests/run.sh
```

It checks script syntax and runs the question-detection, `next-question.sh`, dashboard, quick-action, mode
and answerer tests against a fake meeting and a stand-in model server. No microphone, speech model, Ollama
or API key is needed, and nothing goes over the network.
