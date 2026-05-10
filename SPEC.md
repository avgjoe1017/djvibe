# vibedj — Product Spec

**One-line:** A DJ for AI agents. While the LLM works, your podcast or audiobook plays. When it's your turn to think and respond, it crossfades to ambient.

**Status:** v1 shipped — bash CLI, mpv audio engine, Claude Code hook integration.
**Owner:** Joe
**Last updated:** May 9, 2026

---

## 1. Problem

Vibe coding produces a structurally weird attention pattern. While you're typing or thinking through what to ask next, you need cognitive headroom — silence, drone, or low-vocab ambient. While the agent is working — five seconds, sometimes ninety — your attention is unallocated. You watch the spinner. You scroll Twitter. You drift.

Most "music for coding" tooling treats both windows identically: lo-fi all the way through. That defaults the high-attention windows (yours) and the low-attention windows (the agent's) to the same audio. It also wastes the agent-running window, which is structurally identical to a commute or a dishwashing block — passive listening capacity that the user already has but isn't using.

## 2. Insight

Invert the audio strategy.

- **Agent-running time → passive listening capacity.** Fill it with substantive content (podcasts, audiobooks, lectures, conference talks).
- **User-input time → cognitive workspace.** Protect it with ambient or silence so you can think.

The conceptual move that makes this not just "another music app for coders" is treating *AI as a system that reshapes the user's attention budget*, not as a system that produces output. The audio is the visible artifact of that reframing.

## 3. Solution

vibedj is a CLI plus audio engine plus Claude Code hook config that:

- Holds two long-form audio streams open simultaneously (active spoken-word + ambient/drone)
- Crossfades between them when the agent transitions between working and waiting
- Reads agent state via Claude Code's native lifecycle hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop`, `Notification`)
- Persists spoken-word position across sessions so audiobooks/long podcasts pick up where you left off
- Stays out of the way: no UI, no notifications, no analytics

## 4. Users & Use Cases

### Primary user
Solo developer or builder using Claude Code (or similar agentic dev tools) for multi-hour sessions, who wants to convert LLM-running dead time into something productive or pleasurable.

### Adjacent users
- Knowledge workers using agentic non-coding tools (Cowork, Claude in Chrome) — pending hook availability
- Researchers running long compute jobs (different trigger source needed)
- People with ADHD profiles who find total silence under-stimulating during deep work but full-volume music distracting during input

### Use cases
- **Audiobook progression**: finish a 12-hour audiobook over a week of coding sessions
- **Podcast queue burndown**: chew through long-form interviews during the 30s–2min run windows
- **Lecture / conference talk catch-up**: passive learning during agent execution
- **Language immersion**: target-language listening during run windows when you can't simultaneously read

## 5. Non-Goals

Explicit non-goals keep scope honest:

- **Not a podcast player.** No feed parsing, no subscriptions, no episode discovery. Point it at files. Discovery and queuing live in Spotify, Apple Podcasts, Pocket Casts, etc.
- **Not a focus app.** No Pomodoro, no streaks, no "deep work" gamification.
- **Not multi-user / not collaborative.** Solo audio for solo work.
- **Not DRM-cracking.** Open m4b audiobooks work. Audible-with-DRM does not. Deliberate boundary.
- **Not a recommender (in v1).** v1 plays files in directory order or shuffle. Smart selection is a v2 idea, not the core product.

## 6. Functional Requirements

### v1 (shipped)

| Capability | Detail |
|---|---|
| Dual audio streams | Two `mpv` instances, IPC-controlled, independent volumes |
| State transitions | `run` (podcast on, ambient out), `idle` (ambient on, podcast out), `stop` (engine off) |
| Idempotent transitions | `vibedj run` is a no-op if already in run state — safe for high-frequency hooks |
| Crossfade | Default 1.2s, configurable via `VIBEDJ_FADE_MS` |
| Position persistence | Spoken-word stream resumes via mpv's `--save-position-on-quit` |
| Hook integration | 5 Claude Code hooks: SessionStart, UserPromptSubmit, PreToolUse, Stop, Notification |
| Transport controls | `next`, `prev`, `skip` (+30s), `back` (-15s), `status` |
| Volume tuning | `VIBEDJ_VOLUME` (podcast), `VIBEDJ_AMBIENT_VOLUME` (ambient), 0-100 |
| Logging | Timestamped state transitions logged to `~/.vibedj/vibedj.log` |

### v2 (planned)

- **Smart resume**: if a podcast track ends mid-idle, auto-advance so you don't return to dead air
- **Transition lockfile**: kill in-flight fades when a new transition fires (handles permission-grant race condition)
- **macOS menu bar app**: current track display, manual run/idle toggle, per-stream volume sliders
- **Per-project content folders**: `~/.vibedj/<project-slug>/podcast` and `/ambient`, auto-detected from cwd
- **Spotify integration** (scope TBD): two real options as of May 2026 — (a) use Spotify's "Save to Spotify CLI" (released May 7, 2026) to publish a vibedj-curated private podcast into the user's Spotify library; (b) use the Web API `/me/player/queue` endpoints for live queue control. (b) got harder in Feb 2026 — Premium-only Dev Mode, 5-user cap, several endpoints removed. Pick a path when this becomes a real priority; don't conflate the two like the prior version of this line did.
- **Apple Podcasts AppleScript bridge**: native integration with subscribed feeds
- **Idle detection**: pause both streams if no keyboard/mouse activity for N minutes (don't blast audio at an empty room)

### v3 (speculative)

- **Tool-agnostic event source**: support Cursor, VS Code, Cowork, Claude Code via plugin layer
- **Run-window analytics**: surface short-form episodes when historical run windows are short, long-form when long
- **Attention-budget export**: "you spent 2.3 hours in agent-run windows this week — 47 min more than last week"
- **Content packs**: curated bundles (founder interviews, programming history, ML/AI lectures) as opt-in starter content

## 7. Technical Architecture

### Components

```
┌──────────────────────────────────────────────────────────────┐
│  Claude Code session                                         │
│    ├─ SessionStart  ──▶  vibedj start                        │
│    ├─ UserPromptSubmit ─▶ vibedj run                         │
│    ├─ PreToolUse    ──▶  vibedj run    (idempotent no-op)    │
│    ├─ Stop          ──▶  vibedj idle                         │
│    └─ Notification  ──▶  vibedj idle                         │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  vibedj CLI      │  bash, ~250 LOC
                    │  (idempotent)    │
                    └────────┬─────────┘
                             │ writes /tmp/vibedj.state
                             │ sends mpv IPC commands via socat
                             ▼
              ┌──────────────────────────────┐
              │  mpv (podcast)  mpv (ambient)│
              │  --idle         --idle       │
              │  --input-ipc-server          │
              │  Unix sockets at /tmp/       │
              └──────────────────────────────┘
                             │
                             ▼
                  CoreAudio / PulseAudio / ALSA
```

### Why this design

- **No daemon.** mpv processes ARE the daemons; the CLI is stateless and just sends IPC commands. Simpler to reason about, fewer failure modes.
- **mpv as audio engine.** Cross-platform, supports IPC natively, handles every audio format that matters, has position persistence built in.
- **Bash + socat + jq-free JSON.** Zero language runtime dependencies beyond what's already on a developer's Mac. Total install footprint: one binary + two brew packages.
- **State file in `/tmp`.** Survives across CLI invocations within a session, cleared on reboot — desirable.

### Hook event mapping

| Event | Why this event | Action |
|---|---|---|
| `SessionStart` | Claude Code starts, engine should be ready | `vibedj start` (boots mpv, ends in idle) |
| `UserPromptSubmit` | User just hit enter — agent is about to work | `vibedj run` |
| `PreToolUse` | Agent calling a tool — definitely working. Permission-grant resume is observed in v1 but not formally documented in the hooks API; if it stops working on a Claude Code release, switch the resume-trigger to `PostToolUse`. | `vibedj run` (no-op when already running) |
| `Stop` | Agent's turn complete — user about to think | `vibedj idle` |
| `Notification` | Agent needs user attention (permission, input) | `vibedj idle` |
| `SessionEnd` | Session terminating | Not wired in v1 — without it, two mpv daemons stay alive until reboot or manual `vibedj stop`. Candidate for v2 (`vibedj stop`). |

### Performance

- Idempotent transitions: ~5ms (read state file, compare string, exit)
- Active transition: 1.2s (the crossfade duration itself; fades run in parallel via `&` and `wait`)
- Memory: two mpv processes, ~30-50MB combined
- CPU: negligible when paused, single-digit % when actively decoding audio

### Platform support

- **Tested:** macOS (primary dev target).
- **Should work:** Linux. mpv, socat, bash, Unix sockets are all standard.
- **Does not work natively:** Windows. Unix domain sockets at `/tmp/vibedj-*.sock`, `kill -0`, mpv's `--input-ipc-server` Unix-socket mode, and the bash signal-handling all assume POSIX. The author develops on Windows 11 and runs vibedj under WSL2; that path works.
- **Windows-native port** is a v3 candidate, not v2. Would require: PowerShell rewrite, mpv's Windows named-pipe IPC mode (`\\.\pipe\vibedj-podcast`), and a different process-lifecycle strategy.

## 8. UX Flows

### First-run setup
1. User clones repo, runs `./install.sh`
2. Script checks for `mpv` and `socat`, offers `brew install` if missing
3. Binary copied to `~/.local/bin/vibedj`
4. Audio dirs created at `~/.vibedj/podcast/` and `~/.vibedj/ambient/`
5. Hook config printed; user merges into `~/.claude/settings.json`
6. User drops audio files into the two folders
7. Next Claude Code session: SessionStart hook fires, engine boots, ambient begins

### Normal session loop
```
[ambient playing]
  user types prompt + enter
[crossfade to podcast over 1.2s]
  agent works, calls tools, returns answer
[crossfade to ambient over 1.2s]
  user reads, thinks, types next prompt
  ...
```

### Permission-prompt flow (the v1 fix in action)
```
[podcast playing — agent working]
  agent requests permission for a tool call
  Notification fires → vibedj idle
[crossfade to ambient]
  user reads prompt, thinks, approves
  agent calls tool → PreToolUse fires → vibedj run
[crossfade back to podcast]
```

### Edge cases & failure modes

| Case | Behavior |
|---|---|
| `mpv` not installed | `vibedj start` exits with brew install instructions |
| Empty audio folders | mpv logs idle, vibedj continues — silence on that channel |
| Crash mid-session | `rm /tmp/vibedj-*.{sock,pid,state}` and re-run `vibedj start` |
| User walks away mid-session | v1: keeps playing. v2: idle detection auto-pauses |
| Concurrent transitions (race) | Second fade overwrites first; volumes self-correct on next transition |
| Audio file mid-fade cutoff | User runs `vibedj back` (-15s) to recover dropped audio |

## 9. Configuration

| Variable | Default | Purpose |
|---|---|---|
| `VIBEDJ_DIR` | `~/.vibedj` | Root directory for content + state |
| `VIBEDJ_VOLUME` | 65 | Podcast/audiobook playback volume (0-100) |
| `VIBEDJ_AMBIENT_VOLUME` | 40 | Ambient playback volume (0-100) |
| `VIBEDJ_FADE_MS` | 1200 | Crossfade duration in milliseconds |
| `VIBEDJ_INSTALL_DIR` | `~/.local/bin` | Where the `vibedj` binary lands |

## 10. Roadmap & Phases

### Phase 1: Personal MVP — current
- **Goal:** Joe uses it daily for 30 days, validates the core insight
- **Done when:** ≥15 working days of usage in next 30 days, self-reported audiobook/podcast progression
- **Kill condition:** <10 days of usage in 30 days, OR not adopted into default Claude Code routine

### Phase 2: Quality of life
- **Triggers:** Phase 1 daily-driver passed
- **Scope:** Smart resume, transition lockfile, menu bar app, idle detection
- **Done when:** Comfortable enough to recommend to a peer with no caveats

### Phase 3: Externalize
- **Triggers:** Phase 2 complete, peer feedback positive
- **Scope:** GitHub release, announcement post, README polish, demo video
- **Done when:** Public repo with installation instructions a stranger can follow

### Phase 4 (open question): Productize?
See Section 12. Path forks here.

## 11. Distribution Strategy

If/when externalized:

- **Launch surface:** GitHub repo + a "You're Using AI Wrong" newsletter post framing the attention-budget insight
- **Frame:** Not "another tool for vibe coders" but "AI reshapes your attention budget — here's a tool that takes that seriously"
- **Discovery channels:** Hacker News, r/ClaudeAI, builder Twitter, Anthropic Discord, Claude Code-specific communities
- **Anchor asset:** The insight, not the code. The README leads with the inversion frame, not the install instructions.

## 12. Defensibility / Moat

Honest assessment: **low moat as a standalone product.** The core idea is the insight, not the implementation. Anyone reading the README could rebuild it in a weekend.

Plausible moat sources:

| Moat type | Cost | Likelihood it works |
|---|---|---|
| **Content layer** — curated audio packs for builders (talks, founder interviews, audiobook recs) | Medium ongoing | Medium. Real value, but content curation is a different business. |
| **Distribution moat** — become THE thing Claude Code power users install first | Low (one good launch) | Medium. Network-effects via README virality + builder Twitter. |
| **Integration moat** — native Anthropic-blessed feature in Claude Code | None (acquihire/contribution path) | Low but high-payoff. Requires making vibedj visible enough that Anthropic notices. |
| **Brand moat** — vibedj == attention-aware audio for AI work | Medium (consistent voice across artifacts) | Medium. Pairs with "You're Using AI Wrong" frame. |

**Most likely outcome:** open source, ~modest adoption, becomes a credibility signal in the builder portfolio. Joins Citation Gap as a "this person notices things others don't" artifact.

## 13. Open Questions

1. **Cross-tool support:** is the insight replicable for non-coding agentic tools (Cowork, Claude in Chrome)? Hooks API needs to exist for any of those for vibedj to extend cleanly.
2. **Audio fragmentation hostility:** does chopping a podcast into 30-second listening windows objectively hurt comprehension vs. listening through? Needs real-user testing. Concrete plan: one week with an audiobook (lower per-second density, higher redundancy), one week with long-form podcast interviews (higher density). Self-rate comprehension and retention at the end of each week, comparing against a recent same-format listen with no fragmentation.
3. **Long-run threshold:** should there be a third state — "long agent run" (>2min) where ambient comes back partially as a "you've been listening passively for a while" cue?
4. **Naming:** is "DJ" the right metaphor or does "valet" / "context-aware audio" / "agent-aware audio" position the product better for non-coder audiences?
5. **CBS conflict-of-interest:** does a personal open-source project with no monetization need clearance? (Probably no, but worth confirming if Phase 4 becomes paid product.)

## 14. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Claude Code restructures the hooks API (renames or removes events) | Medium | Abstract the hook layer; build for stability of `Stop` + `UserPromptSubmit` semantics, not exact event names |
| Hook semantics drift while names stay stable — e.g., `PreToolUse`'s firing pattern around permission grants changes between Claude Code versions | Medium | Test the permission-grant resume flow on each Claude Code minor version; have a `PostToolUse` fallback ready as the resume-trigger |
| Audio fragmentation makes podcasts unlistenable | Medium | Test with audiobook (lower per-second density) before committing to podcast positioning |
| User walks away, vibedj keeps blasting | High | Add idle detection in Phase 2 |
| Anthropic builds this natively into Claude Code | Low-medium | If it happens, frame vibedj's existence as the proof-point that drove it; pivot focus to the insight as content asset |
| Permission-grant race condition causes audible glitch | Low | Add transition lockfile in Phase 2; for now, brief volume overshoot is tolerable |

## 15. Success Metrics

### Personal (Phase 1) — measurement window: May 9 → June 8, 2026
- vibedj running on ≥15 of those 30 days
- Self-reported: "I'm getting through more audiobooks/podcasts since installing"
- Negative signal to watch for: I find myself disabling it during important agent work

### External (Phase 3+)
- 100 GitHub stars in first 30 days
- ≥5 unsolicited public mentions from non-friends
- ≥1 feature request from a recognized builder
- ≥1 fork with substantive contributions

## 16. Kill Conditions (90-day rule)

If by **August 9, 2026**:
- Personal usage <10 days/month, AND
- No external traction, AND
- No clear strategic value (portfolio credibility, content fuel, etc.)

The triple-AND is intentional: any one of the three holding keeps vibedj alive. Personal-tool-only with no audience is a valid resting state, not a failure.

→ archive in Builder's Diary, document the learning ("the inversion insight was real, but the artifact didn't stick"), move on.

If personal usage is high but external traction is zero → keep as personal tool, do not invest in Phase 3+. That's still a win.

## 17. Appendix: Files & Layout

```
vibedj/
├── README.md              # user-facing intro, install, usage
├── SPEC.md                # this document
├── install.sh             # bootstrap script  [planned — referenced by README, not yet written]
├── hooks-snippet.json     # Claude Code hook config to merge
└── bin/
    └── vibedj             # main CLI (bash, ~220 LOC)

~/.vibedj/                 # runtime state directory
├── podcast/               # spoken-word audio (mp3, m4a, m4b, etc.)
├── ambient/               # ambient/drone audio
├── vibedj.log             # timestamped transition log
└── .watch-later/          # mpv position persistence

/tmp/                      # ephemeral runtime
├── vibedj.state           # current state: "run" | "idle"
├── vibedj-podcast.sock    # mpv IPC socket (podcast)
├── vibedj-ambient.sock    # mpv IPC socket (ambient)
├── vibedj-podcast.pid     # mpv process pid (podcast)
└── vibedj-ambient.pid     # mpv process pid (ambient)
```
