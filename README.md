# vibedj

A DJ for AI agents.

While the LLM is working, vibedj plays your podcast or audiobook.
When it's your turn to think and respond, it crossfades to ambient.

The premise: passive listening capacity is unlocked while the agent runs.
The moments you actually need to think are the rare ones — protect them with silence/drone.

## How it works

Two `mpv` processes hold open IPC sockets. A tiny CLI tells them which one is the foreground.
Claude Code hooks fire on lifecycle events and call the CLI:

| Event              | Action       | Result                          |
|--------------------|--------------|---------------------------------|
| `SessionStart`     | `vibedj start` | engine up, ambient playing    |
| `UserPromptSubmit` | `vibedj run`   | crossfade → podcast           |
| `PreToolUse`       | `vibedj run`   | resume podcast after permission prompts (idempotent — no-op if already running) |
| `Stop`             | `vibedj idle`  | crossfade → ambient           |
| `Notification`     | `vibedj idle`  | (agent needs you) → ambient   |

State is tracked in `/tmp/vibedj.state` so `run` and `idle` short-circuit
when already in the target state. `PreToolUse` fires constantly during agent
work but costs ~nothing thanks to the early-exit.

Crossfade defaults to 1.2s.

## Install

```bash
./install.sh
```

This will:
- check for `mpv` and `socat` (offers `brew install` if missing)
- copy `vibedj` to `~/.local/bin/`
- create `~/.vibedj/podcast/` and `~/.vibedj/ambient/`
- print the JSON to merge into `~/.claude/settings.json`

Then drop audio files into the two folders. Anything mpv can play works
(mp3, m4a, m4b for audiobooks, flac, ogg, opus, etc.).

For audiobooks, m4b chapters work great — mpv resumes position via
`--save-position-on-quit` so you pick up where you left off across sessions.

## Manual use (without Claude Code hooks)

```bash
vibedj start    # bring up the engine
vibedj run      # podcast on, ambient out
vibedj idle     # ambient on, podcast out
vibedj next     # skip podcast track
vibedj back     # rewind 15s (caught half a sentence at the transition)
vibedj status
vibedj stop
```

## Tuning

```bash
export VIBEDJ_VOLUME=70          # podcast loudness 0-100
export VIBEDJ_AMBIENT_VOLUME=35  # ambient loudness 0-100
export VIBEDJ_FADE_MS=1500       # crossfade duration
```

## Known v1 limitations

- **Mid-sentence cutoff**: when run→idle hits, you may lose the last second or two of
  podcast audio under the fade. Use `vibedj back` to scrub backward when you re-engage.
- **Concurrent transitions**: if `Notification` (idle) and `PreToolUse` (run) fire
  within the 1.2s fade window, the second fade kicks off before the first finishes
  and volumes can overshoot briefly. Self-corrects on the next transition.
  Fix candidate: a transition lockfile that kills in-flight fades.
- **Single user, single agent**: no multi-session coordination. Fine for solo use.
- **Mac-tested**: should work on Linux (mpv + socat are cross-platform). Untested on Windows.

## Roadmap candidates

- v2: Spotify integration via the new Save-to-Spotify CLI, so the podcast queue
  is your actual Spotify library
- v2: macOS menu bar status item (current track, manual run/idle toggle)
- v2: Apple Podcasts AppleScript bridge for true app integration
- v2: per-project audio folders (different content for different repos)
- v2: smart resume — if a podcast track ends mid-idle, auto-advance so you don't
  hit dead air on the next run
