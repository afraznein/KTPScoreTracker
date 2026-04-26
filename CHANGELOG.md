# Changelog

All notable changes to KTPScoreTracker will be documented in this file.

## [1.1.1] - 2026-04-25

### Added
- **Adopted `ktp_version_reporter` shared include** — plugin now registers with the fleet-wide `amx_ktp_versions` rcon command (ADMIN_RCON). Output reports name, version, build SHA, and build time alongside other KTP plugins. See KTPMatchHandler 0.10.116 for the canary release introducing the include.
- **`compile.sh` build-info generation** — git short SHA + UTC build time written to `build_info.inc` and baked into the .amxx so the rcon command can report what's actually deployed.

## [1.0.0] - 2026-02-26

### Added
- **Initial release** - Verbose capture scoring plugin
- Real-time chat notifications for flag captures with player + point attribution
- Batched multi-player capture display (all cappers shown in one message)
- Per-player capture stats tracked across the match
- End-of-match capture summary sorted by points
- HLStatsX-compatible server log entries: `KTP_CP_CAPTURED`, `ktp_cap_score`, `ktp_cap_summary`
- Match state integration via KTPMatchHandler forwards (ktp_match_start/ktp_match_end)
