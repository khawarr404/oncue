---
name: oncue
description: Live copilot for meetings, interviews and client calls on Google Meet, Zoom, Teams or any call app on this computer. Transcribes the call locally (speaker output + mic), alerts the agent whenever someone asks a question, and shows a short suggested answer as a desktop pop-up and in the chat; at the end writes meeting notes (summary, decisions, actions). Use this whenever the user says "start oncue", "listen to my meeting", "listen to my interview", "help me answer in the meeting", "take notes during my call", "prep for my call", "interview mode" (or another mode), "stop oncue" (or "start/stop meeting assist"), or asks for live help, preparation or notes for a call that is about to start or is running, even if they don't name the skill.
---

# oncue

Help the user during a live call: listen through a local transcript, suggest answers to questions people ask
them, and write notes afterwards. Speech is transcribed on the user's machine and audio never leaves it; only transcript text you read
goes to your model.

Supported: Linux with PipeWire (audio capture). Works in any agent that can run shell commands: Claude Code,
Cursor, Codex, Gemini CLI, GitHub Copilot, Windsurf and others.

Paths: scripts are in this skill's `scripts/` folder (call it `$SKILL`). The user's data lives in
`$ONCUE_HOME` (default `~/oncue`): `CONTEXT.md` (their cheat sheet), `prep.md` (optional, prep for the
next call), `mode.txt` (current mode; missing means meeting), `modes/` (their own modes), `vocab.txt`
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
  copy button, earlier answers, live transcript, the mode menu and quick-action buttons; `C` toggles a
  compact answer-only view for a small window beside the call; `A` `K` `R` `F` are the quick actions).
- Read now, so answers come quickly later: `CONTEXT.md`, `prep.md` if it exists, and the current mode file
  (`$SKILL/scripts/mode.sh --path` prints it). Tell the user in one line that you are listening and in
  which mode.

**C. No coding agent (or the user wants their own model):** `$SKILL/scripts/up.sh --answer` also starts
`answer.py`, which answers with a local Ollama model (default) or an API set in the environment; see the
README. While `$ONCUE_HOME/run/answer.pid` holds a running process, do not answer questions yourself
(each would get two answers); you can still write notes at the end.

Alerts fire only on lines from others that name the user (or a mis-hearing in `name.txt`), ask something
within 60 s of the user speaking, or ask a question containing a `topics.txt` word; chatter between others
is ignored.

## When a question arrives

Speed matters more than polish: the user is waiting in a live conversation. A line with `ACTION:` in it is
a quick action, not a question: see the next section.

0. Cheap mode check: `cat $ONCUE_HOME/mode.txt`. If it changed since you last read the mode file, read the
   new one (`mode.sh --path`). Follow the mode for length, format and what never to do.
1. Read the last ~15 lines of the transcript (`tail -n 15 "$(cat $ONCUE_HOME/sessions/LATEST)"`)
   for context; the alert line alone can be a fragment.
2. Decide whether it is really a question for the user. Skip small talk and rhetorical or self-answered
   questions **silently**: no notify, no chat message at all, so the session's context stays small. If
   unsure whether it is for the user, answer briefly.
3. Write a suggested answer: one or two short, plain sentences the user can say out loud (or what the
   mode asks for, e.g. a STAR outline in interview mode), based on `CONTEXT.md`, `prep.md` and what you
   know. Never invent numbers, facts or experience; if the cheat sheet doesn't cover it, suggest an honest
   holding line ("Good question, I'll check and come back today").
4. Show it with `$SKILL/scripts/notify.sh "<question, short>" "<answer>"` (desktop pop-up plus `answers.md`)
   and also post it in the chat as:
   **💬 Q:** question  ·  **Say:** answer

Speech-to-text mistakes are normal (names, jargon); read through them. Lines say THEM (anyone heard through
the speakers) or ME (the user's mic); the transcript cannot tell individual people apart.

## Quick actions

The dashboard's buttons (and keys `A` `K` `R` `F`) write `[HH:MM:SS] ACTION: <name>` into the transcript.
They reach you like a question: as a Monitor line, or from `next-question.sh` as
`QUESTION [10:05:00] ACTION: recap`. The user asked for these, so never skip them. Read the transcript
(the last ~15 lines; for a recap, the lines of the last ~5 minutes), follow the mode, then:

| Action | Write | Show with |
|---|---|---|
| `answer` | An answer to the latest thing THEM asked the user, even if no alert fired (it may be a few lines back). | `notify.sh "<their question, short>" "<answer>"` |
| `clarify` | One line in plain words: what they just asked and what they probably want. | `notify.sh "Clarify" "<line>"` |
| `recap` | 3-5 short bullets (`- `) of the last ~5 minutes: points, decisions, open questions. | `notify.sh "Recap" "<bullets>"` |
| `followup` | 1-2 short, good questions the user could ask them now (use `prep.md` if it has some). | `notify.sh "Follow-up" "<questions>"` |

Multi-line text is fine, but no blank lines (they cut the answer short on the dashboard). Also post it in
the chat in the usual short form.

## Modes

A mode tells you how to answer for this kind of call. Built in: `meeting` (default), `interview`, `sales`,
`client`, `standup`, `negotiation` (files in this skill's `modes/`). The user's own modes, or their versions
of built-in ones, are `$ONCUE_HOME/modes/<name>.md`.

- "Interview mode", "switch to sales", ...: run `$SKILL/scripts/mode.sh <name>`, then read the file it
  prints. `mode.sh` alone lists modes. The user can also switch in the dashboard's Mode menu.
- "Make a mode for ...": write `$ONCUE_HOME/modes/<name>.md` (lowercase name; sections Purpose, Answers,
  What matters, Never, like the built-in ones), then set it.
- Interview mode answers only from the user's real CV and experience; negotiation mode coaches from the
  user's own targets. Never invent experience, employers or figures in any mode.

## "Prep for my call"

Before a call, build `prep.md` so answers are grounded in the user's real material.

1. Ask for what is missing (one short message): their CV or résumé (file path), the job ad or agenda (text
   or URL), the company, the names of the people on the call, and the call type.
2. Read what they gave. Research the company and the attendees with whatever web search or fetch tools you
   have (public facts only: what the company does, recent news, the people's roles). If you have no web
   tools, skip research and say so in one line.
3. Update `$ONCUE_HOME/CONTEXT.md` with lasting facts about the user (role, experience, projects, numbers
   they are happy to say). Keep what is there; replace the template's placeholder lines.
4. Write `$ONCUE_HOME/prep.md` from `assets/prep.template.md`: the call, key facts (with sources), likely
   questions with short answers from the user's real material (interview: STAR, one line each), questions
   to ask them, the user's own numbers and limits, watch-outs. Overwrite the previous call's prep.
5. Add the attendees' names, the company and its products and jargon to `vocab.txt` (comma separated), and
   project or role words to `topics.txt`.
6. Set the mode for the call type (`mode.sh interview`, ...).
7. Show a short summary and ask the user to correct anything wrong.

Never invent experience, employers, results or figures: anything not in the user's material stays out, or
goes under watch-outs as a gap with an honest answer.

## "Stop oncue"

1. Run `$SKILL/scripts/stop.sh` (listener, watcher and answerer; the dashboard keeps showing the meeting,
   `--all` stops it too). In Claude Code also stop the Monitor (TaskStop).
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
