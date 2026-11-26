# How it works

## Pieces

| Script | Job |
|---|---|
| `listen.py` | Records speakers (`THEM`) and mic (`ME`) with `pw-record`, cuts speech at 0.7 s pauses, transcribes each piece with faster-whisper, appends `[HH:MM:SS] THEM: text` to `transcript.txt`. |
| `watch.sh` | Follows the transcript and prints lines that are questions for you; appends them to `questions.log`. |
| `next-question.sh` | Blocking "give me the next question" for agents that cannot stream output. Keeps a read position per meeting. |
| `notify.sh` | Desktop pop-up and append to `answers.md`. |
| `dashboard.py` | Local web page (standard library only, no external files) reading the session folder. |
| `start.sh` / `up.sh` / `stop.sh` | Start in foreground / start everything detached / stop. Processes are tracked with pid files in `~/oncue/run/`. |

## Alert rules

A `THEM` line alerts when it:

1. contains your name or a mis-hearing from `name.txt`;
2. contains `?` and you spoke in the last 60 s;
3. has a sentence ending in `?` that contains a word from `topics.txt`;
4. says *can you / could you / why / how* and you spoke in the last 60 s.

Words match whole: `Sam` matches "Sam?" but not "samples". With `--no-mic` there are no `ME` lines, so
only rules 1 and 3 can fire: add topic words.

The agent then reads the last ~15 transcript lines, decides whether it is really a question for you
(small talk is skipped silently), and writes a one or two sentence answer from `CONTEXT.md`.

## Speech model

faster-whisper on CPU, int8, `beam_size=1`, `vocab.txt` as the initial prompt. `small.en` is the default
after a benchmark on an Intel Core Ultra 7 155H laptop (no GPU) with jargon-heavy clips: as accurate as
`large-v3-turbo` and about 3x faster (1.5 s per 7 s of audio). Details and numbers:
[platforms.md](../skills/oncue/references/platforms.md).

## Limits

- The transcript cannot tell individual people apart: everyone through the speakers is `THEM`.
- Speech-to-text mishears names and jargon. Add them to `vocab.txt` and `name.txt`.
- Linux with PipeWire only for live mode, for now.
