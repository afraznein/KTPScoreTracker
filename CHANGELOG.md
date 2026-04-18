# Changelog

All notable changes to KTPScoreTracker will be documented in this file.

## [1.0.0] - 2026-02-26

### Added
- **Initial release** - Verbose capture scoring plugin
- Real-time chat notifications for flag captures with player + point attribution
- Batched multi-player capture display (all cappers shown in one message)
- Per-player capture stats tracked across the match
- End-of-match capture summary sorted by points
- HLStatsX-compatible server log entries: `KTP_CP_CAPTURED`, `ktp_cap_score`, `ktp_cap_summary`
- Match state integration via KTPMatchHandler forwards (ktp_match_start/ktp_match_end)
