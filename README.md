# oncue

**Stay on cue in meetings, interviews and client calls.** oncue is a live copilot for AI coding agents.
It listens to your Google Meet, Zoom or Teams call on your own computer, notices when someone asks *you* a
question, and puts a short suggested answer on screen within seconds. When the call ends it writes the
notes: summary, decisions, actions.

Works as an [Agent Skill](https://agentskills.io) in **Claude Code, Cursor, Codex, Gemini CLI, GitHub
Copilot, Windsurf** and any other agent that can run shell commands.

> **Private by design.** Audio is transcribed locally with [faster-whisper](https://github.com/SYSTRAN/faster-whisper).
> No audio is uploaded. Transcripts stay in `~/oncue`. (The agent you use reads the transcript
> to write answers, so text goes wherever your agent's model runs.)

## Features

- **Live local transcript** of both sides of any call app: what your speakers play (`THEM`) and your
  microphone (`ME`). No meeting bot joins the call.
- **Smart question alerts.** Fires only when a question is meant for you:
  - someone says your name (or a usual mis-hearing of it),
  - someone asks a question within 60 s of you speaking,
  - a question mentions one of your project words.
  Chatter between other people is ignored.
- **Suggested answers** of one or two plain sentences you can say out loud, based on your own cheat
  sheet (`CONTEXT.md`). It never invents numbers: when the cheat sheet does not cover something you get an
  honest holding line.
- **Desktop pop-up** for every answer, plus a **live dashboard** at `http://127.0.0.1:8765`: the
  question just heard, the answer in large type with a copy button, earlier answers and the transcript.
  Press `C` for a compact view beside the call, `S` for a sound cue, `Y` to copy.
- **Meeting notes** at the end: summary, decisions, actions with owners, open questions, and every
  question you were asked.
- **Learns your vocabulary**: names and jargon in `vocab.txt` steer the speech model's spelling.
- **Paste mode** (`oncue-paste`) for macOS, Windows or plain chat apps: paste a question, get
  talking points in under 120 words.
- Small and hackable: bash, awk and two Python files. No server, no account, MIT licence.

## Requirements

| | Live mode (`oncue`) | Paste mode (`oncue-paste`) |
|---|---|---|
| OS | **Linux with PipeWire** (Ubuntu 22.10+, Fedora 34+, most current distros) | Any |
| Tools | Python 3.10+, `pw-record`; optional `notify-send`, `uv` | None |
| Disk | About 1.5 GB (Python packages + `small.en` speech model) | None |
| Agent | Any agent that runs shell commands | Any chat agent |

macOS and Windows audio capture are on the [roadmap](skills/oncue/references/platforms.md).
Help wanted: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Quick start

```bash
git clone https://github.com/khawarr404/oncue.git
cd oncue
./install.sh                                   # links the skills into ~/.claude/skills and ~/.agents/skills
skills/oncue/scripts/setup.sh         # one time: Python env + speech model
```

Then, in your agent:

1. *"Set up oncue."* It fills `~/oncue/CONTEXT.md` with you (your role, the project,
   people, numbers you are happy to say) and asks for your name and jargon.
2. Just before the call: *"Start oncue."* (Add *"I'm on speakers"* if you have no headphones.)
3. Open `http://127.0.0.1:8765` next to the call.
4. After the call: *"Stop oncue."* Notes land in `~/oncue/sessions/<date-time>/notes.md`.

Per-tool install details (plugin marketplace, Cursor, Codex, Gemini CLI, Copilot, Windsurf, `npx skills`):
**[docs/setup.md](docs/setup.md)**.

## Tool support

| Agent | How questions arrive | Status |
|---|---|---|
| Claude Code | Streams `watch.sh` through the Monitor tool: instant | Primary path (the original skill was built on it) |
| Cursor, Codex, Gemini CLI, Copilot, Windsurf | `up.sh`, then loops on `next-question.sh` (blocks until a question arrives; none are lost between calls) | Should work; not yet tested in a real meeting. Reports welcome |
| Any chat app (claude.ai, ChatGPT, ...) | Paste mode: you paste the question | Works anywhere |

## Your files

Everything lives in `~/oncue` (change with `ONCUE_HOME`):

| File | What it is |
|---|---|
| `CONTEXT.md` | Your cheat sheet. Answers are only as good as this. |
| `name.txt` | Line 1: your first name. Then one mis-hearing per line (`Siobhan`, `Shivon`, ...). |
| `vocab.txt` | Names, products and jargon, comma separated. Spelling hint for the speech model. |
| `topics.txt` | Optional project words; a question containing one always alerts. |
| `sessions/<date-time>/` | `transcript.txt`, `questions.log`, `answers.md`, `notes.md` for each meeting. |

## How it works

```
speakers ─┐                     ┌─> transcript.txt ─> watch.sh ─> questions.log ─┬─> agent writes answer
          ├─ pw-record ─> listen.py (faster-whisper)                            │    └─> notify.sh: pop-up + answers.md
mic ──────┘                                                                     └─> dashboard.py (127.0.0.1:8765)
```

More in [docs/how-it-works.md](docs/how-it-works.md): alert rules, speech model benchmark, settings.

## Settings

| Variable | Default | |
|---|---|---|
| `ONCUE_HOME` | `~/oncue` | Data folder |
| `ONCUE_MODEL` | `small.en` | faster-whisper model (`base.en` for slow machines, `small` for non-English) |
| `ONCUE_THREADS` | `min(6, cores)` | CPU threads for speech |
| `ONCUE_BEAM` | `1` | Beam size (5 is slower and was no more accurate) |
| `ONCUE_PORT` | `8765` | Dashboard port |
| `ONCUE_NAME` | from `name.txt` | Override the name list (`Sam|Sem`) |
| `ONCUE_NO_POPUP` | unset | Set to skip desktop pop-ups |

Start options: `--no-mic` (on speakers, to avoid hearing others twice), `--language de` (with a
multilingual model), `--model base.en`.

## Consent

Recording or transcribing other people can require their agreement, depending on where you and they are.
Tell the people in your meetings. You are responsible for using this lawfully.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Contributing

Pull requests welcome, especially macOS and Windows audio capture. Run `bash tests/run.sh` first.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

[MIT](LICENSE)
