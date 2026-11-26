# Troubleshooting

| Problem | Fix |
|---|---|
| `MISSING: pw-record` | Your system has no PipeWire (or not its tools). Install `pipewire-bin` (Debian/Ubuntu) or `pipewire-utils` (Fedora). PulseAudio-only and macOS/Windows are not supported yet; use paste mode. |
| Transcript stays empty | Check `~/oncue/run/listen.log`. Is the call's audio playing through the default output? Switching headphones mid-call: stop, then start again. |
| My own words show as `THEM` | You are on speakers. Restart with `--no-mic`, or use headphones. |
| No alerts for questions to me | Add the ways your name gets misheard to `name.txt` (one per line), and project words to `topics.txt`. Say *"check transcript"* to catch up. |
| Too slow (answers lag) | `ONCUE_MODEL=base.en`, or tune `ONCUE_THREADS` (about your performance-core count). |
| Dashboard says "Dashboard offline" | Run `python3 skills/oncue/scripts/dashboard.py`; port in use: `--port 8766`. |
| `next-question.sh` prints a watcher warning | Run `scripts/up.sh` again; it only starts what is missing. |
| No pop-ups | Install `notify-send` (`libnotify-bin`). Answers still show in the chat and dashboard. |
| Skill not found by my agent | Check the folder for your tool in [setup.md](setup.md), and that the link points to the repo's `skills/oncue`. |
