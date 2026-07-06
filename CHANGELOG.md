# Changelog

All notable changes to KTPScoreTracker will be documented in this file.

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
