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
| *"Start oncue"* | Listener, question watcher and dashboard start. Open `http://127.0.0.1:8765`. |
| *"I'm on speakers"* | Starts with `--no-mic` so others are not transcribed twice. |
| *"Check transcript"* | The agent reads recent lines and answers anything it missed. |
| *"Stop oncue"* | Stops listening and writes `notes.md`. |

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

### Paste mode (any OS, any chat app)

Install `skills/oncue-paste` (or paste its `SKILL.md` into a chat app's custom instructions or
project knowledge). Say *"paste mode"*, then paste each question as it comes.

## Uninstall

```bash
skills/oncue/scripts/stop.sh --all
rm -r ~/.claude/skills/oncue* ~/.agents/skills/oncue* ~/.copilot/skills/oncue* 2>/dev/null
```

Your meetings stay in `~/oncue` until you delete that folder yourself.
