# How it works

## Pieces

| Script | Job |
|---|---|
| `listen.py` | Records speakers (`THEM`) and mic (`ME`) with `pw-record`, cuts speech at 0.7 s pauses, transcribes each piece with faster-whisper, appends `[HH:MM:SS] THEM: text` to `transcript.txt`. |
| `watch.sh` | Follows the transcript and prints lines that are questions for you; appends them to `questions.log`. |
| `next-question.sh` | Blocking "give me the next question" for agents that cannot stream output. Keeps a read position per meeting. |
| `notify.sh` | Desktop pop-up and append to `answers.md`. |
| `dashboard.py` | Local web page (standard library only, no external files) reading the session folder; quick-action buttons and mode menu. |
| `mode.sh` | Lists modes or sets the current one (`mode.txt`). |
| `answer.py` | Optional answerer with your own model (Ollama, Anthropic or OpenAI-compatible), standard library only. |
| `start.sh` / `up.sh` / `stop.sh` | Start in foreground / start everything detached (`--answer` adds the answerer) / stop. Processes are tracked with pid files in `~/oncue/run/`. |

## Alert rules

A `THEM` line alerts when it:

1. contains your name or a mis-hearing from `name.txt`;
2. contains `?` and you spoke in the last 60 s;
3. has a sentence ending in `?` that contains a word from `topics.txt`;
4. says *can you / could you / why / how* and you spoke in the last 60 s.

Words match whole: `Sam` matches "Sam?" but not "samples". With `--no-mic` there are no `ME` lines, so
only rules 1 and 3 can fire: add topic words.

The agent then reads the last ~15 transcript lines, decides whether it is really a question for you
(small talk is skipped silently), and writes a short answer from `CONTEXT.md` and `prep.md`, in the
style of the current mode.

## Quick actions

The dashboard's Answer, Clarify, Recap and Follow-up buttons (keys `A`, `K`, `R`, `F`) append a line such
as `[10:05:00] ACTION: recap` to `transcript.txt`. `watch.sh` passes `ACTION` lines through unchanged, so
they reach the agent by the same path as questions: the Monitor stream, `next-question.sh` (as
`QUESTION [10:05:00] ACTION: recap`) or `answer.py`. The answer comes back through `notify.sh` with
"Recap", "Clarify", "Follow-up" or the question as its title. The dashboard leaves `ACTION` lines out of
the transcript view and the question count.

Any web page you visit can send requests to `127.0.0.1`, so the dashboard only accepts these requests
from its own page: each one must carry a random token that is new every time the dashboard starts and
is only in the page it served, the `Host` must be `127.0.0.1` or `localhost`, and only the four action
names (and known mode names) are accepted. The dashboard listens on `127.0.0.1` only.

## Modes

A mode is a short markdown file: purpose, answer length and format, what matters, what never to do.
Built-in modes live in `skills/oncue/modes/`; files in `~/oncue/modes/` add modes or replace built-in
ones with the same name. `mode.txt` holds the current mode (missing means `meeting`); `mode.sh`, the
dashboard menu and the agent all change it, and the agent and `answer.py` re-read it for each question.

## Prep

*"Prep for my call"* has the agent read your CV, the job ad or agenda, research the company and attendees
(when it has web tools), update `CONTEXT.md`, write `prep.md` (from `assets/prep.template.md`), add names
and jargon to `vocab.txt` and `topics.txt`, and set the mode. During the call answers draw on `prep.md`.

## The answerer (`answer.py`)

For use without a coding agent. It follows `questions.log` with its own read position
(`.answer_offset`, separate from `next-question.sh`'s `.read_offset`), and for each line sends the model
the mode file, `CONTEXT.md`, `prep.md` (each cut to 6000 characters), the last 15 transcript lines (the
last 5 minutes for a recap) and the line. A reply of `SKIP` (not a question for you) writes nothing.
Answers go through `notify.sh`. Questions already waiting when it starts are skipped, and a failed
request is logged to `run/answer.log` and not retried: a late answer is no use in a live call.

| Provider | Endpoint | Where text goes |
|---|---|---|
| `ollama` (default) | `ONCUE_OLLAMA_URL` + `/api/chat` | Stays on your computer |
| `anthropic` | Messages API | Anthropic |
| `openai` | `OPENAI_BASE_URL` + `/chat/completions` | OpenAI or the compatible service you set |

## Speech model

faster-whisper on CPU, int8, `beam_size=1`, `vocab.txt` as the initial prompt. `small.en` is the default
after a benchmark on an Intel Core Ultra 7 155H laptop (no GPU) with jargon-heavy clips: as accurate as
`large-v3-turbo` and about 3x faster (1.5 s per 7 s of audio). Details and numbers:
[platforms.md](../skills/oncue/references/platforms.md).

## Limits

- The transcript cannot tell individual people apart: everyone through the speakers is `THEM`.
- Speech-to-text mishears names and jargon. Add them to `vocab.txt` and `name.txt`.
- Linux with PipeWire only for live mode, for now.
