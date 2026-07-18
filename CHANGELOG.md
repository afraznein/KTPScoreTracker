# Changelog

All notable changes to KTPScoreTracker will be documented in this file.

## [1.1.4] - 2026-07-18

### Fixed
- **ST-01: warmup control-point captures were logged under the live matchid.** `dod_control_point_captured` (`KTP_CP_CAPTURED`) and `dod_score_event` (`ktp_cap_score`) called `log_message` unconditionally with `g_matchId`, which is deliberately kept populated across the h1→h2 map change. During the h2 warmup window (post-map-change, pre-`.ready`) ordinary caps were tagged with the prior half's live matchid and were indistinguishable from official in-match captures to any HLStatsX consumer correlating by matchid. Both log lines are now gated on `g_matchActive`, mirroring the counter gate the in-memory stats already had (the leak v1.1.3 closed for counters but not for log output). Chat feedback is unaffected.
- **ST-02: deferred capture-flush read the player name by a stale slot.** `dod_score_event` batches the scoring slot id and flushes 0.1s later via `set_task`; `flush_capture` called `get_user_name()` on the stored slot with no connection/identity check, so a disconnect (or a new player landing in the recycled slot) within that window could print a blank or wrong name. Now snapshots the userid at add time and, at flush, only trusts the live name when the slot is still connected and still that userid; otherwise falls back to "a departed player".

## [1.1.3] - 2026-07-08

### Fixed
- **Match linkage restored for explicit-OT matches** (2026-07-06 wave-2 plugin assessment). `ktp_match_start` copied `matchId` only when `half == 1`, but `.ktpOT`/`.draftOT` matches fire their first start with half=101 (halves are 1, 2, or 100+round) — so every `KTP_CP_CAPTURED`/`ktp_cap_score`/`ktp_cap_summary`/capout line in an explicit-OT match carried `matchid=""`. Worse variant (confirmed reachable): `.forcereset` does not fire `ktp_match_end`, so the *previous* match's id survived and the next explicit-OT match logged all its captures under the stale id. Now the id is copied on every `ktp_match_start`, and per-match stats reset on a changed id OR half==1 — the half==1 arm covers 1.3-Community ids, which carry no timestamp and repeat identically when the same queue restarts after a `.forcereset` (a changed-id-only boundary would leak the aborted attempt's caps into the restart).
- **Substitutes no longer inherit a leaver's capture stats.** Per-player cap stats are slot-indexed with no disconnect reset — a sub joining into a leaver's slot mid-match inherited their caps/points and was credited with them in the end-of-match summary and `ktp_cap_summary` log lines. The slot's stats now clear in `client_disconnected`.
- **Half-2 pre-live warmup caps no longer count as match stats.** `g_matchActive` persisted across the h1→h2 map change (globals survive map changes in extension mode), so caps during half-2 warmup — before the half went live — accumulated into match stats under the live matchid. `plugin_init` now disarms match attribution (and clears the pending capture batch) at every map boundary; `ktp_match_start` re-arms it when the half goes live. `g_matchId` intentionally still carries across the mid-match map change.

## [1.1.2] - 2026-07-06

### Fixed
- **Capout recovery hardened for the pre-changelevel window** (2026-07-05 full-stack review #13). `award_capout_recovery` runs from the "Final Scores" log event — timelimit expiry, BEFORE changelevel, the exact window the project's score-restoration warning covers. Old defects: no `dodx_has_gamerules()` guard, so the recovery decision could be computed from mixed sources (`dodx_get_team_score` silently falls back to the message-tracked score when gamerules is unavailable, while the write path needs real gamerules), and the code relied on dodx's native-error abort semantics instead of an explicit checked contract — a failure would surface as AMXX runtime-error spam in the intermission window rather than a clean audit line. Now: `logevent_final_scores` bails early (with a log line) if gamerules is unavailable, and the `dodx_set_team_score` write is explicitly checked — the failure branch logs `KTP_CAPOUT_RECOVERY_FAILED` and awards nothing. (Note: the checked branch becomes fully live once dodx honors its documented return-0 contract instead of raising a native error — queued module-side; either way no failure can produce the success broadcast/chat/log.)
- **`dod_score_event` guards the player id** before logging/batching — matches the guard the stats path already had; prevents malformed HLStatsX `ktp_cap_score` lines on edge ids. Also fixes a real pre-existing wedge: a garbage id was appended to the pending batch *before* `get_user_name` raised its runtime error, and every later flush attempt then aborted before the state reset — permanently poisoning the capture batch until map change.

### Docs
- In-file header/version comment synced (was stale at 1.1.0); missing 1.1.0 CHANGELOG entry below restored; README version footer corrected (was 1.0.0).

## [1.1.1] - 2026-04-25

### Added
- **Adopted `ktp_version_reporter` shared include** — plugin now registers with the fleet-wide `amx_ktp_versions` rcon command (ADMIN_RCON). Output reports name, version, build SHA, and build time alongside other KTP plugins. See KTPMatchHandler 0.10.116 for the canary release introducing the include.
- **`compile.sh` build-info generation** — git short SHA + UTC build time written to `build_info.inc` and baked into the .amxx so the rcon command can report what's actually deployed.

## [1.1.0] - 2026-04-01

### Added
- **Timelimit capout recovery** — detects when a team captures all control points in the same engine frame that timelimit fires (which prevents the game DLL from processing the capout bonus). Hooks the "Final Scores" log event to catch intermission start, reads `CP_owner` for all CPs via DODX, compares the team score against a snapshot taken at the last CP flip, and awards the stolen `mp_clan_scoring_bonus_allies/axis` via `dodx_set_team_score` + `dodx_broadcast_team_score` when the engine didn't. One-shot per half; logs `KTP_CAPOUT_RECOVERY` for HLStatsX/audit.

_(This entry was reconstructed 2026-07-06 — the 1.1.0 release shipped without a CHANGELOG entry; details from the in-file changelog.)_

## [1.0.0] - 2026-02-26

### Added
- **Initial release** - Verbose capture scoring plugin
- Real-time chat notifications for flag captures with player + point attribution
- Batched multi-player capture display (all cappers shown in one message)
- Per-player capture stats tracked across the match
- End-of-match capture summary sorted by points
- HLStatsX-compatible server log entries: `KTP_CP_CAPTURED`, `ktp_cap_score`, `ktp_cap_summary`
- Match state integration via KTPMatchHandler forwards (ktp_match_start/ktp_match_end)
