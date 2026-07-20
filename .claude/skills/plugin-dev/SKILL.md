---
name: plugin-dev
description: Use BEFORE writing or modifying any KTPScoreTracker Pawn code — capture-logging/matchid attribution rules, the async-flush identity rule, and the compile/review/stage/verify workflow. Also use when planning a change, to know which invariants it touches.
---

# KTPScoreTracker Development

This plugin emits real-time capture chat + HLStatsX-format log lines on a
production fleet (24 instances). Its log output is a data feed, not just
UI — downstream tooling parses it. Follow every rule below; when a rule and
your instinct disagree, the rule wins — each one was paid for with a
production incident.

## Hard safety rules
- **NEVER restart game servers** or issue LinuxGSM control commands without the
  operator's explicit permission in the current conversation.
- Deploys are staged as `KTPScoreTracker.amxx.new` in each instance's plugins
  dir and swap at the 03:00 ET nightly restart. Never hot-swap the live `.amxx`.
- Run the `ktp-code-review` agent on any nontrivial change BEFORE compiling for deploy.

## Architecture constraints
- **Extension mode**: KTPAMXX loads as a ReHLDS extension — there is NO Metamod
  and NO fakemeta. Engine/game events come only from DODX forwards
  (`dod_control_point_captured`, `dod_score_event`) and KTPMatchHandler's
  `ktp_match_start`/`ktp_match_end` forwards. Never add a fakemeta dependency.
- Plugin globals (`g_matchId`, `g_matchActive`, per-slot capture stats) persist
  for the whole server process, not per map — extension mode never restarts the
  plugin on a map change. Any new global needs an explicit reset plan; don't
  assume a map change clears anything.
- **`g_matchId` and `g_matchActive` are deliberately NOT the same lifetime.**
  `g_matchId` intentionally survives the h1→h2 map change (it has to "carry
  across" the half boundary) and is only cleared at full `ktp_match_end`.
  `g_matchActive` is the thing that goes false during warmup/pre-live windows.
  **Any code path that logs or counts a capture must gate on `g_matchActive`,
  not on whether `g_matchId` is populated** — a non-empty matchid does not mean
  "currently live." The in-memory stat counters are gated correctly (v1.1.3);
  when you touch or add a `log_message()` call for a capture/score event,
  gate it the same way or it will tag warmup captures with the live matchid.

## Log output is a consumed data feed
`KTP_CP_CAPTURED`, `ktp_cap_score`, and `ktp_cap_summary` lines are written in
HLStatsX-parseable format and are meant to be correlated by `matchid`. Any
change to line format, field names/order, or matchid semantics can silently
break a downstream parser with no compile-time signal here. Treat format/field
changes as a coordinated change, not a local edit — check for consumers
(HLStatsX `hlstats.pl` parsing rules, any AC/analytics ingestion) before
shipping, and call it out explicitly in the CHANGELOG.

## Async-boundary identity rule
A player **slot index is not an identity**. `dod_score_event` captures a slot
into a pending batch and defers the chat/log flush via `set_task`. Any slot
captured before a deferred task fires may point at a different person (or
nobody) by flush time — slots recycle on disconnect, and `is_user_connected()`
only proves the slot is occupied, not by whom. Capture the **authid or userid
alongside the slot** and revalidate it at flush time; on mismatch, skip the
entry or fall back to a generic label rather than trusting the live slot's
current name. (KTPHLTVRecorder 1.7.2 fixed the same bug class — mirror that
fix shape here.)

## Constants: use dodconst.inc, don't reinvent it
Team values (`ALLIES`/`AXIS` = 1/2) already exist in `dodconst.inc`. Don't add
a local `TEAM_ALLIES`/`TEAM_AXIS` (or similar) duplicate — every call site
building a team-name string should read from the same symbol. Two symbols for
one value is how they silently desync on a future edit.

The shipped source already violates this: `TEAM_ALLIES`/`TEAM_AXIS` are defined
locally and used in the capout-recovery path while `flush_capture` uses
`ALLIES`/`AXIS`. Treat that as legacy — prefer `ALLIES`/`AXIS` in new code and
don't add call sites for the duplicates.

## Pawn checklist (apply to every diff)
- `charsmax(buf)` for every format/copy; watch truncation on composed chat lines.
- Every `set_task` with a deferred id: revalidate identity at flush (see above),
  and make sure disconnect clears that slot's pending/stat state (don't let a
  substitute inherit a leaver's capture stats).
- Check return values of natives that can fail (`dodx_set_team_score`,
  `dodx_has_gamerules()` et al.) — log a distinct failure line, award nothing.
- Comments: short, explain *why*, no ticket/finding IDs, never delete a
  tripwire fact while editing near it. Don't describe a shipped upstream fix's
  dependent code as "not yet live" — check the CLAUDE.md component table for
  current fleet state before writing that kind of comment.

## Never run a destructive simulation inside the working tree
Verifying a fix often means simulating the failure — writing a fake `build.sh`, a
fake artifact, a fake staging dir. Do it in a **verified** scratch dir, never in
the repo:

```bash
T="$(mktemp -d)" || exit 1
[ -n "$T" ] && [ -d "$T" ] || exit 1   # verify BEFORE you cd — this is the whole rule
cd "$T" || exit 1
```

`cd "$T"` with an empty `$T` **silently succeeds and leaves you where you were** —
in the repo. A simulation that then writes `build.sh` overwrites the real one. On
2026-07-16 exactly that truncated a tracked 60-line upstream file to 2 lines and
dropped a junk `.so` into `build/`, where a `find | head -1` could have staged it.
It was caught only because `git status` showed a modification nobody made.

So: verify the scratch dir before `cd`, and **run `git status` after any test that
touches the filesystem** — an unexpected change is the tell. Prefer copying inputs
out to the scratch dir over running tools "in place".

## Workflow
1. **Version bump** (every shipped change): `#define PLUGIN_VERSION` in the
   .sma, new `CHANGELOG.md` section, README header version, TODO.md if applicable.
2. **Compile**: `wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPScoreTracker' && bash compile.sh"`
   (outputs `compiled/`, bakes git SHA + UTC build time into `build_info.inc`
   for the `amx_ktp_versions` rcon, auto-stages to the KTP DoD Server test tree).
3. **Review**: `ktp-code-review` agent before any fleet stage.
4. **Fleet stage**: deploy as `.new` via paramiko (see root CLAUDE.md § SSH);
   verify staged md5 on all 24 active instances.
5. **Post-activation verify** (after the nightly): 24/24 on the new md5, no
   leftover `.new`, and check `/tmp` for cores — `find /tmp -maxdepth 1 -name
   'core.*' -mtime -1` on every host. A game-tree core search proves nothing
   (matches only core.so/core.ini/core.wav).

## Known dependencies (don't break silently)
- Requires KTPMatchHandler's `ktp_match_start`/`ktp_match_end` forwards —
  changes to those forward signatures in KTPMatchHandler require a matching
  update here.
- Requires DODX's CP-tracking forwards (`controlpoints_init`,
  `dod_control_point_captured`, `dod_score_event`).
