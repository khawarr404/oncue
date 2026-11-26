# Platforms

The bundled scripts support **Linux with PipeWire** (most current distributions: Ubuntu 22.10+, Fedora 34+).
They capture the speaker output with `pw-record -P '{ stream.capture.sink=true }'` and the mic with `pw-record`.

Not supported yet (roadmap; contributions welcome, see CONTRIBUTING.md in the repository):
- **macOS:** install BlackHole (virtual audio device), route the call's output through a Multi-Output Device,
  record with `ffmpeg -f avfoundation -i ":BlackHole 2ch"`; pop-ups with `osascript -e 'display notification ...'`.
- **Windows:** record speaker output with WASAPI loopback (`soundcard` or `pyaudiowpatch` Python packages);
  pop-ups with a toast library (`win11toast`).
- **PulseAudio-only Linux:** `parec -d @DEFAULT_SINK@.monitor --rate 16000 --channels 1 --format s16le`.

## Speech model

faster-whisper on CPU, int8, `beam_size=1`, 6 threads, `vocab.txt` as `initial_prompt`. Audio goes to
`transcribe()` as a float32 numpy array (file decoding through PyAV is broken on some installs).

Benchmark, 2026-10-26, Intel Core Ultra 7 155H (Meteor Lake, 22 threads), no GPU: 5 clips of 5-7 s made
with `spd-say` and recorded from the speaker output, full of names and jargon from `vocab.txt`
(71 words). Seconds are per 7 s of audio.

| Model | beam 1 | beam 5 |
|---|---|---|
| `small.en` (default) | 87-92% words right, 1.5 s | 87%, 2.4 s |
| `large-v3-turbo` | 89%, 4.1 s | 89%, 4.6 s |
| `distil-large-v3` | 70%, 7.0 s | 72%, 6.4 s |

`small.en` stays the default: the large models are no more accurate on this jargon and too slow for a
live call (the aim is about 3 s per 7 s clip). `distil-large-v3` ignores the vocab hint. Beam 5 costs time
and gains nothing. Threads: 6 (about the performance-core count) was fastest; 8-16 threads spill onto the
efficiency cores and are slower (2.1-3.0 s). Override with `ONCUE_MODEL`, `ONCUE_BEAM`,
`ONCUE_THREADS`. On slow machines try `base.en`. For non-English meetings use a multilingual model
(`small`) and `--language`.

Known mis-hearings are fixed with data rather than a bigger model: add the word to `vocab.txt`, and for
the user's own name add each mis-hearing to `name.txt` (one per line) so questions still alert.
