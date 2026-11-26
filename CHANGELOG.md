# Changelog

## Unreleased

- Floating answer window (`scripts/float.py`, `up.sh --float`): a small always-on-top window with the
  latest suggested answer in large text, the question it answers, a status line, "question heard… answer
  coming", the quick actions, Copy, a mode menu, compact view and an opacity slider. Same keys as the
  dashboard (`A` `K` `R` `F` `Y` `C`, plus `+` / `-` for opacity). Remembers position, size, opacity and
  compact in `float.json`. tkinter, standard library only. `stop.sh` closes it.
- The dashboard writes its per-start token to `run/dashboard.token` (mode 0600, removed on exit) so local
  programs such as the floating window can use the POST endpoints. Browser protections are unchanged, and
  requests marked `Sec-Fetch-Site: cross-site` are now refused too.

- Ollama: thinking turned off by default (`think: false`) so thinking models such as qwen3 answer
  quickly instead of spending the token budget on reasoning. `ONCUE_OLLAMA_THINK=1` turns it back on.

## 0.2.0 (2026-11-26)

- Quick actions on the dashboard (buttons, also in compact view, and keys `A` `K` `R` `F`): Answer,
  Clarify, Recap, Follow-up. They reach the agent as `ACTION` lines through `watch.sh`, the Monitor
  path and `next-question.sh`. The dashboard's POST requests need a per-start token from its own page,
  a local `Host`, and a known action name.
- Modes: `meeting` (default), `interview`, `sales`, `client`, `standup`, `negotiation`, plus your own in
  `~/oncue/modes/`. `scripts/mode.sh` and a dashboard menu switch them; `mode.txt` holds the current one.
- Prep for a call: the agent turns your CV, the job ad or agenda and research into `prep.md` (template in
  `assets/prep.template.md`), updates `CONTEXT.md`, `vocab.txt` and `topics.txt`, and sets the mode.
- `scripts/answer.py`: optional answerer with your own model, no coding agent needed. Ollama (default,
  offline), Anthropic or any OpenAI-compatible API. Standard library only. Start with `up.sh --answer`;
  `stop.sh` stops it.
- Multi-line answers (recaps) keep all their lines in `answers.md` and the dashboard.
- Tests for quick actions, modes and the answerer (against a stand-in model server).

## 0.1.0 (2026-11-26)

First public release.

- `oncue`: live local transcription (PipeWire + faster-whisper), question alerts, suggested
  answers as desktop pop-ups, live dashboard, meeting notes.
- Works with agents that stream output (Claude Code Monitor) and with one-command-at-a-time agents
  (Cursor, Codex, Gemini CLI, Copilot, Windsurf) through `up.sh` + `next-question.sh`.
- Process tracking by pid files, so the repo works under any folder name.
- `oncue-paste`: paste-a-question talking points for any OS and any chat app.
