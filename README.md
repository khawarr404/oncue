# oncue

**Stay on cue in meetings, interviews and client calls.** oncue is a live copilot for AI coding agents.
It listens to your Google Meet, Zoom or Teams call on your own computer, notices when someone asks *you* a
question, and puts a short suggested answer on screen within seconds. When the call ends it writes the
notes: summary, decisions, actions.

Works as an [Agent Skill](https://agentskills.io) in **Claude Code, Cursor, Codex, Gemini CLI, GitHub
Copilot, Windsurf** and any other agent that can run shell commands.

> **Private by design.** Audio is transcribed locally with [faster-whisper](https://github.com/SYSTRAN/faster-whisper).
> No audio is uploaded. Transcripts stay in `~/oncue`. (The agent you use reads the transcript
> to write answers, so text goes wherever your agent's model runs. With the built-in answerer and Ollama,
> nothing leaves your computer at all; see [Own model](#own-model-ollama-or-an-api).)

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
- **Floating answer window** (`up.sh --float`): a small always-on-top window that shows the latest
  suggested answer and the question it answers, so you can read it while looking at the call. Same quick
  actions and keys as the dashboard, a mode menu, Copy, compact (`C`, answer only) and an opacity slider
  (`+` / `-`) for comfort. It's a normal window and appears in screen shares like any other.
- **Quick actions** on the dashboard, also in compact view: **Answer** (`A`, the latest thing they asked,
  even if no alert fired), **Clarify** (`K`, what they just asked in plain words), **Recap** (`R`, the last
  5 minutes in bullets), **Follow-up** (`F`, good questions to ask them).
- **Modes** that set how answers sound: `meeting` (default), `interview` (only your real experience, STAR
  for behavioural questions), `sales`, `client`, `standup`, `negotiation` (coaching from your own targets).
  Switch by saying *"interview mode"*, in the dashboard, or with `scripts/mode.sh`. Add your own in
  `~/oncue/modes/`.
- **Prep for a call**: give your agent your CV, the job ad or agenda, the company and who you are meeting;
  it researches them (if it has web tools) and writes `prep.md` with likely questions, answers from your
  real material and questions to ask, then sets the mode.
- **Own model, no coding agent needed**: `up.sh --answer` runs a small answerer with a local
  [Ollama](https://ollama.com) model (fully offline) or the Anthropic, OpenAI or any OpenAI-compatible API.
- **Meeting notes** at the end: summary, decisions, actions with owners, open questions, and every
  question you were asked.
- **Learns your vocabulary**: names and jargon in `vocab.txt` steer the speech model's spelling.
- **Paste mode** (`oncue-paste`) for macOS, Windows or plain chat apps: paste a question, get
  talking points in under 120 words.
- Small and hackable: bash, awk and a few standard-library Python files. No cloud service, no account,
  MIT licence.

## Requirements

| | Live mode (`oncue`) | Paste mode (`oncue-paste`) |
|---|---|---|
| OS | **Linux with PipeWire** (Ubuntu 22.10+, Fedora 34+, most current distros) | Any |
| Tools | Python 3.10+, `pw-record`; optional `notify-send`, `uv`, tkinter (`python3-tk`, floating window) | None |
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
2. Optional, before an important call: *"Prep for my call"* (or *"prep for my interview at ..."*) with
   your CV, the job ad or agenda and who you are meeting.
3. Just before the call: *"Start oncue."* (Add *"I'm on speakers"* if you have no headphones, or
   *"interview mode"* to switch mode.)
4. Open `http://127.0.0.1:8765` next to the call, or ask for the floating window (*"start oncue with the
   floating window"*, or `up.sh --float`).
5. After the call: *"Stop oncue."* Notes land in `~/oncue/sessions/<date-time>/notes.md`.

Per-tool install details (plugin marketplace, Cursor, Codex, Gemini CLI, Copilot, Windsurf, `npx skills`):
**[docs/setup.md](docs/setup.md)**.

## Tool support

| Agent | How questions arrive | Status |
|---|---|---|
| Claude Code | Streams `watch.sh` through the Monitor tool: instant | Primary path (the original skill was built on it) |
| Cursor, Codex, Gemini CLI, Copilot, Windsurf | `up.sh`, then loops on `next-question.sh` (blocks until a question arrives; none are lost between calls) | Should work; not yet tested in a real meeting. Reports welcome |
| No coding agent | `up.sh --answer`: the built-in answerer with Ollama or an API | Tested against a stand-in server; reports welcome |
| Any chat app (claude.ai, ChatGPT, ...) | Paste mode: you paste the question | Works anywhere |

## Your files

Everything lives in `~/oncue` (change with `ONCUE_HOME`):

| File | What it is |
|---|---|
| `CONTEXT.md` | Your cheat sheet. Answers are only as good as this. |
| `name.txt` | Line 1: your first name. Then one mis-hearing per line (`Siobhan`, `Shivon`, ...). |
| `vocab.txt` | Names, products and jargon, comma separated. Spelling hint for the speech model. |
| `topics.txt` | Optional project words; a question containing one always alerts. |
| `prep.md` | Prep for the next call (written by *"prep for my call"*). |
| `mode.txt` | The current mode (missing means `meeting`). |
| `modes/<name>.md` | Your own modes, or your versions of built-in ones. |
| `float.json` | The floating window's position, size, opacity and compact setting. |
| `sessions/<date-time>/` | `transcript.txt`, `questions.log`, `answers.md`, `notes.md` for each meeting. |

## How it works

```
speakers ─┐                     ┌─> transcript.txt ─> watch.sh ─> questions.log ─┬─> agent (or answer.py) writes answer
          ├─ pw-record ─> listen.py (faster-whisper)                            │    └─> notify.sh: pop-up + answers.md
mic ──────┘                                                                     └─> dashboard.py (127.0.0.1:8765)
                                                                                      └─> float.py (always-on-top window)
dashboard quick actions (Answer, Clarify, Recap, Follow-up) ─> "ACTION: recap" lines in transcript.txt
```

More in [docs/how-it-works.md](docs/how-it-works.md): alert rules, speech model benchmark, settings.

## Settings

| Variable | Default | |
|---|---|---|
| `ONCUE_HOME` | `~/oncue` | Data folder |
| `ONCUE_MODEL` | `small.en` | faster-whisper model (`base.en` for slow machines, `small` for non-English) |
| `ONCUE_THREADS` | `min(6, cores)` | CPU threads for speech |
| `ONCUE_BEAM` | `1` | Beam size (5 is slower and was no more accurate) |
| `ONCUE_PORT` | `8765` | Dashboard port (the floating window uses it too) |
| `ONCUE_NAME` | from `name.txt` | Override the name list (`Sam|Sem`) |
| `ONCUE_NO_POPUP` | unset | Set to skip desktop pop-ups |
| `ONCUE_PROVIDER` | `ollama` | Answerer (`up.sh --answer`): `ollama`, `anthropic` or `openai` |
| `ONCUE_LLM_MODEL` | `llama3.2` / `claude-haiku-5-5` / `gpt-4o-mini` | Answerer model (default per provider) |
| `ONCUE_OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama server |
| `ANTHROPIC_API_KEY` | unset | For `ONCUE_PROVIDER=anthropic` |
| `OPENAI_API_KEY` | unset | For `ONCUE_PROVIDER=openai` (optional for local compatible servers) |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Any OpenAI-compatible endpoint, e.g. `https://openrouter.ai/api/v1` |
| `ONCUE_LLM_TIMEOUT` | `30` | Seconds before an answer request gives up |
| `ONCUE_OLLAMA_THINK` | unset | Set to `1` to let thinking models (qwen3, deepseek-r1) reason first; off by default because it is slow |

Start options: `--no-mic` (on speakers, to avoid hearing others twice), `--language de` (with a
multilingual model), `--model base.en`, `--answer` (`up.sh` only: also start the answerer), `--float`
(`up.sh` only: also open the floating answer window; needs a desktop session and Python's tkinter).

## Own model (Ollama or an API)

Without a coding agent, or to keep answers off the cloud, oncue can answer by itself:

```bash
ollama pull llama3.2                         # once; https://ollama.com
skills/oncue/scripts/up.sh --answer          # listener, watcher, dashboard and answerer
python3 skills/oncue/scripts/answer.py --test  # optional: check your settings with one sample question
skills/oncue/scripts/stop.sh                 # after the call
```

The answerer reads `CONTEXT.md`, `prep.md`, the current mode and the last lines of the transcript, skips
questions that are not for you, and handles the dashboard's quick actions. Answers show in the dashboard
and as pop-ups. Errors go to `~/oncue/run/answer.log`. Meeting notes still need an agent (or paste the
transcript into any chat).

**Where your text goes:**

- `ollama` (default): the model runs on your computer. Fully offline; nothing leaves the machine.
- `anthropic`, `openai` or any OpenAI-compatible endpoint (OpenRouter, ...): the transcript lines, your
  `CONTEXT.md`, `prep.md` and the mode text are sent to that provider with each question. Use it only if
  that is acceptable for the call. API keys are read from the environment and never written to logs.

## Consent

Recording or transcribing other people can require their agreement, depending on where you and they are.
Tell the people in your meetings. You are responsible for using this lawfully.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Contributing

Contributions are welcome, especially macOS and Windows audio capture and reports from Cursor, Codex,
Gemini CLI, Copilot and Windsurf users.

1. **Fork** this repo and create a branch.
2. Make your change and run `bash tests/run.sh` (no microphone or speech model needed).
3. Open a **pull request**. CI runs the tests; the maintainer reviews and merges.

Bugs and ideas: [open an issue](https://github.com/khawarr404/oncue/issues/new/choose). Security problems:
report privately (see [SECURITY.md](SECURITY.md)). Details in [CONTRIBUTING.md](CONTRIBUTING.md); please
follow the [code of conduct](CODE_OF_CONDUCT.md).

## Licence

[MIT](LICENSE)
