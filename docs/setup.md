# Setup guide

Three steps for every tool: **get the repo**, **install the skills where your agent looks for them**,
**run the one-time setup**. Then ask your agent to *"set up oncue"*.

```bash
git clone https://github.com/khawarr404/oncue.git ~/oncue-repo
cd ~/oncue-repo
```

(Keep the repo apart from the data folder `~/oncue`.)

## 1. Install the skills

### Easiest: the install script

```bash
./install.sh                 # ~/.claude/skills and ~/.agents/skills (covers most tools)
./install.sh copilot         # ~/.copilot/skills for GitHub Copilot
./install.sh claude agents copilot --copy   # copies instead of symlinks
```

Symlinks (the default) mean `git pull` updates the skill everywhere.

### Or: `npx skills` (any supported agent)

[`skills`](https://github.com/vercel-labs/skills) is an open-source installer that knows where each agent
keeps its skills:

```bash
npx skills add khawarr404/oncue -g
```

### Per tool

| Tool | Where it reads skills | Notes |
|---|---|---|
| **Claude Code** | `~/.claude/skills/` (you), `.claude/skills/` (one project) | Or as a plugin, below |
| **Cursor** | `~/.cursor/skills/`, `~/.agents/skills/`; also reads `~/.claude/skills/` | If a skill shows twice, remove one link |
| **Codex** | `~/.agents/skills/`, `.agents/skills/` | |
| **Gemini CLI** | `~/.gemini/skills/`, `~/.agents/skills/` | Or `gemini skills install <repo-url>` |
| **GitHub Copilot (VS Code)** | `~/.copilot/skills/`, `.github/skills/` | `./install.sh copilot` |
| **Windsurf** | `~/.agents/skills/` | |

Folder layouts change; check your tool's docs if a skill does not show up.

### Claude Code as a plugin

The repo is also a Claude Code plugin marketplace:

```bash
claude plugin marketplace add khawarr404/oncue
claude plugin install oncue@oncue
```

(Inside a session: `/plugin marketplace add khawarr404/oncue`.)

## 2. One-time setup (live mode, Linux)

```bash
skills/oncue/scripts/setup.sh
```

It checks for `pw-record`, creates a Python environment in `~/oncue/.venv` (with `uv` if you have
it), downloads the `small.en` speech model (about 1.5 GB in total) and creates your data folder with a
cheat-sheet template. Safe to run again. Your agent runs it for you on first use if you skip this.

Check your system first if unsure:

```bash
command -v pw-record notify-send python3
```

## 3. Fill your cheat sheet

Ask your agent: *"Set up oncue."* It will:

- fill `~/oncue/CONTEXT.md` (role, project, people, numbers, weak spots) from what it knows and
  what you tell it,
- write your first name and its mis-hearings to `name.txt`,
- add names and jargon to `vocab.txt`, and project words to `topics.txt`.

The better the cheat sheet, the better the answers.

## Using it

| Say | What happens |
|---|---|
| *"Prep for my call"* | The agent asks for your CV, the job ad or agenda, the company and attendees, researches them and writes `prep.md`. |
| *"Start oncue"* | Listener, question watcher and dashboard start. Open `http://127.0.0.1:8765`. |
| *"I'm on speakers"* | Starts with `--no-mic` so others are not transcribed twice. |
| *"Interview mode"* | Switches the answer style (also `sales`, `client`, `standup`, `negotiation`, `meeting`). |
| *"Check transcript"* | The agent reads recent lines and answers anything it missed. |
| *"Stop oncue"* | Stops listening and writes `notes.md`. |

### Prep for a call

Before an interview, sales call or negotiation, say *"prep for my call"* and give the agent:

- your CV or résumé (a file path),
- the job ad or agenda (paste it or give a URL),
- the company and the names of the people you are meeting,
- the call type.

It researches the company and people if it has web tools (it says so if not), updates `CONTEXT.md`,
writes `~/oncue/prep.md` (likely questions with short answers from your real experience, questions to ask
them, key facts, your own numbers), adds names and jargon to `vocab.txt` and `topics.txt`, and sets the
mode. Check `prep.md`: answers can only be as true as it is.

### Modes

```bash
skills/oncue/scripts/mode.sh              # list modes; * marks the current one
skills/oncue/scripts/mode.sh interview    # switch
```

Or pick one in the dashboard's Mode menu, or tell the agent. Your own mode: copy a file from
`skills/oncue/modes/` to `~/oncue/modes/<name>.md` and edit it (a file with a built-in name replaces that
mode).

### Quick actions

In the dashboard (also in compact view): **Answer** (`A`) answers the latest thing they asked even if no
alert fired, **Clarify** (`K`) restates what they just asked, **Recap** (`R`) gives the last 5 minutes in
bullets, **Follow-up** (`F`) suggests questions to ask them. The answer appears in the dashboard within
seconds, like any other.

### Claude Code

Questions arrive instantly through the Monitor tool. Nothing else to do.

### Cursor, Codex, Gemini CLI, Copilot, Windsurf

The agent runs `scripts/up.sh` (everything starts detached) and then calls `scripts/next-question.sh` in a
loop. Each call waits up to 4 minutes and returns `QUESTION ...`, `NONE` (call again) or `STOPPED`.
Questions that arrive between calls are queued.

Tips:

- Use agent/auto-run mode so the agent can keep calling the script without asking you each time.
- If your agent stops looping (some tools cap tool calls per turn), say *"keep listening"*.
- If your tool kills long commands, ask it to call `next-question.sh 60` instead.

This path has passed automated tests but has not yet been tried in a real meeting in each tool. Please
open an issue with what you find.

### No coding agent: your own model

`answer.py` answers by itself with a local model (Ollama, fully offline) or an API.

Ollama quick start:

```bash
# install Ollama first: https://ollama.com/download
ollama pull llama3.2                              # about 2 GB; any chat model works
python3 skills/oncue/scripts/answer.py --test     # one sample question: checks the setup
skills/oncue/scripts/up.sh --answer               # start everything, then open http://127.0.0.1:8765
skills/oncue/scripts/stop.sh                      # after the call
```

Another model: `ONCUE_LLM_MODEL=qwen2.5:7b`. A small model answers faster; on a laptop without a GPU,
3B models are a good start.

An API instead (the transcript lines, `CONTEXT.md`, `prep.md` and the mode are then sent to that provider):

```bash
export ONCUE_PROVIDER=anthropic ANTHROPIC_API_KEY=...            # default model claude-haiku-5-5
export ONCUE_PROVIDER=openai OPENAI_API_KEY=...                  # default model gpt-4o-mini
export ONCUE_PROVIDER=openai OPENAI_BASE_URL=https://openrouter.ai/api/v1 OPENAI_API_KEY=... ONCUE_LLM_MODEL=...
```

Keep keys in your shell profile or a password manager, not in the repo. Errors (wrong key, server down)
go to `~/oncue/run/answer.log`; the answerer keeps running. Do not also let a coding agent answer at the
same time, or every question gets two answers.

### Paste mode (any OS, any chat app)

Install `skills/oncue-paste` (or paste its `SKILL.md` into a chat app's custom instructions or
project knowledge). Say *"paste mode"*, then paste each question as it comes.

## Uninstall

```bash
skills/oncue/scripts/stop.sh --all
rm -r ~/.claude/skills/oncue* ~/.agents/skills/oncue* ~/.copilot/skills/oncue* 2>/dev/null
```

Your meetings stay in `~/oncue` until you delete that folder yourself.
