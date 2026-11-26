---
name: oncue
description: Live copilot for meetings, interviews and client calls on Google Meet, Zoom, Teams or any call app on this computer. Transcribes the call locally (speaker output + mic), alerts the agent whenever someone asks a question, and shows a short suggested answer as a desktop pop-up and in the chat; at the end writes meeting notes (summary, decisions, actions). Use this whenever the user says "start oncue", "listen to my meeting", "listen to my interview", "help me answer in the meeting", "take notes during my call", "stop oncue" (or "start/stop meeting assist"), or asks for live help or notes for a call that is about to start or is running, even if they don't name the skill.
---

# oncue

Help the user during a live call: listen through a local transcript, suggest answers to questions people ask
them, and write notes afterwards. Speech is transcribed on the user's machine and audio never leaves it; only transcript text you read
goes to your model.

Supported: Linux with PipeWire (audio capture). Works in any agent that can run shell commands: Claude Code,
Cursor, Codex, Gemini CLI, GitHub Copilot, Windsurf and others.

Paths: scripts are in this skill's `scripts/` folder (call it `$SKILL`). The user's data lives in
`$ONCUE_HOME` (default `~/oncue`): `CONTEXT.md` (their cheat sheet), `vocab.txt`
(names and jargon for spelling), `name.txt` (line 1 their first name, then one mis-hearing of it per line),
optional `topics.txt` (project words; a question with one of them always alerts), and
`sessions/<date-time>/` with `transcript.txt`, `questions.log`, `answers.md` and `notes.md`.

## First run (setup)

If `$ONCUE_HOME/.venv` does not exist, run `$SKILL/scripts/setup.sh` (installs faster-whisper,
downloads the speech model, about 1.5 GB). It supports Linux with PipeWire; on other systems explain what
is missing using `references/platforms.md` rather than improvising audio capture, and offer the
`oncue-paste` skill instead (the user pastes questions; works on any system).

Then make the cheat sheet useful, because suggested answers can only be as good as it is: if `CONTEXT.md`
is still the template, offer to fill it from what you already know about the user's project (this
conversation, their docs, memory), and ask for their name for `name.txt` and names or terms for `vocab.txt`.

## "Start oncue"

Pick the path that matches your tools. If the user is on speakers rather than headphones, pass `--no-mic`
to the start script, otherwise their mic picks up the other people twice. With `--no-mic` only the name and
topic rules alert, so suggest adding topic words.

**A. You can stream a background command's output (Claude Code's Monitor tool):**
1. Run `$SKILL/scripts/start.sh` with Bash `run_in_background` (it runs until stopped).
2. Arm the Monitor tool with `$SKILL/scripts/watch.sh`, description "questions in the meeting", timeout
   the maximum. Re-arm it each time it expires while the meeting runs. Each output line is one question.
3. Start the live web view if it isn't running (`curl -s 127.0.0.1:8765/api/state` fails): run
   `python3 $SKILL/scripts/dashboard.py` with `run_in_background`.

**B. You can only run one command at a time (Cursor, Codex, Gemini CLI, Copilot, Windsurf, ...):**
1. Run `$SKILL/scripts/up.sh` (starts listener, question watcher and dashboard detached; returns at once).
2. Loop: run `$SKILL/scripts/next-question.sh 240`. It blocks until a question arrives and prints
   `QUESTION <line>` (answer it as below, then call it again), `NONE` (nothing yet: call it again), or
   `STOPPED` (meeting over: write notes). Questions that arrive between calls are kept, never lost. Keep
   looping without asking the user between calls; they are in a meeting.

Then, either way:
- Give the user http://127.0.0.1:8765 (the question just heard, the suggested answer in large text with a
  copy button, earlier answers, live transcript; `C` toggles a compact answer-only view for a small window
  beside the call).
- Read `CONTEXT.md` now so answers come quickly later. Tell the user in one line that you are listening.

Alerts fire only on lines from others that name the user (or a mis-hearing in `name.txt`), ask something
within 60 s of the user speaking, or ask a question containing a `topics.txt` word; chatter between others
is ignored.

## When a question arrives

Speed matters more than polish: the user is waiting in a live conversation.

1. Read the last ~15 lines of the transcript (`tail -n 15 "$(cat $ONCUE_HOME/sessions/LATEST)"`)
   for context; the alert line alone can be a fragment.
2. Decide whether it is really a question for the user. Skip small talk and rhetorical or self-answered
   questions **silently**: no notify, no chat message at all, so the session's context stays small. If
   unsure whether it is for the user, answer briefly.
3. Write a suggested answer: one or two short, plain sentences the user can say out loud, based on
   `CONTEXT.md` and what you know. Never invent numbers or facts; if the cheat sheet doesn't cover it, suggest
   an honest holding line ("Good question, I'll check and come back today").
4. Show it with `$SKILL/scripts/notify.sh "<question, short>" "<answer>"` (desktop pop-up plus `answers.md`)
   and also post it in the chat as:
   **💬 Q:** question  ·  **Say:** answer

Speech-to-text mistakes are normal (names, jargon); read through them. Lines say THEM (anyone heard through
the speakers) or ME (the user's mic); the transcript cannot tell individual people apart.

## "Stop oncue"

1. Run `$SKILL/scripts/stop.sh` (listener and watcher; the dashboard keeps showing the meeting, `--all`
   stops it too). In Claude Code also stop the Monitor (TaskStop).
2. Read the whole transcript and write `notes.md` in the session folder:
   - **Summary** (3-5 lines)
   - **Decisions**
   - **Actions** (owner: task, due date if said)
   - **Open questions**
   - **Questions asked to me** (`questions.log` lists every alert; say whether the suggested answer was used)
3. Post a short version in the chat. Offer to update the user's project docs or task list from it.

## Good to know

- Switching audio devices (e.g. connecting headphones) mid-call: run stop.sh then start again.
- Missed alerts: the user can say "check transcript"; read the recent lines and answer anything pending.
- Wrong spellings: add the word to `vocab.txt` (used as a hint by the speech model on the next piece).
  The user's name heard wrong: add that spelling to `name.txt` on a new line so questions to them still alert.
- Speech model: set by benchmark in `listen.py`; `ONCUE_MODEL` overrides it (`references/platforms.md`).
- Consent: recording or transcribing others may need their agreement depending on where they are; if the
  user hasn't said their colleagues know, mention it once, briefly, at start.
