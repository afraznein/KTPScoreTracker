# KTP Score Tracker v1.1.4

Verbose capture scoring plugin for KTP Day of Defeat servers. Outputs real-time capture notifications to chat and logs detailed HLStatsX-compatible entries to the server log.

## Features

- Real-time chat notifications when flags are captured (who captured, how many points)
- Batched multi-player capture display (all cappers shown in one line)
- Per-player capture stats tracked across the match
- End-of-match capture summary printed to chat (connected players only — a capper who left before match end is omitted)
- HLStatsX-compatible server log entries for future stats integration
- **Timelimit capout recovery** — awards a capout bonus the engine drops (see below)

### Timelimit Capout Recovery

⚠️ **This mutates the final score.** It is the one feature here that does more
than report.

When a team captures the last control point in the *same engine frame* that
`mp_timelimit` fires, the game DLL never processes the capout bonus — the team
caps out but is not awarded for it. This plugin detects that case (CP ownership
change within `CAPOUT_RECOVERY_WINDOW`, 2.0s, of the timelimit) and awards the
missing bonus via DODX, announcing it in chat.

Guarded so it can fire at most once per half (`g_capoutRecoveryDone`), and
hardened for the pre-changelevel window where gamerules may already be torn down
— if the award cannot be made safely it is skipped rather than half-applied.

Outcomes are logged either way: `KTP_CAPOUT_RECOVERY` on success,
`KTP_CAPOUT_RECOVERY_FAILED` when the bonus could not be awarded. If a final
score is ever disputed, grep for these first.

The bonus amount comes from `mp_clan_scoring_bonus_allies` /
`mp_clan_scoring_bonus_axis` (read only — map configs set them). Recovery is
skipped when the relevant cvar is `<= 0`.

## Requirements

- **DODX module with CP tracking** (controlpoints_init, dod_control_point_captured, dod_score_event forwards)
- **KTPMatchHandler v0.10.39+** (for ktp_match_start/ktp_match_end forwards) — 0.10.39 is the real floor, not 0.10.1: that release added the 4th `half` parameter to `ktp_match_start` and made it fire on every half. Against 0.10.1–0.10.38 this plugin mis-binds the forward.
- **`ktp_version_reporter` shared include** (KTPAMXX) — enrolls the plugin in the fleet-wide `amx_ktp_versions` rcon (ADMIN_RCON); also a hard build dependency

## Installation

1. Compile the plugin (see Build below)
2. Copy `KTPScoreTracker.amxx` to `addons/ktpamx/plugins/`
3. Add `KTPScoreTracker.amxx` to `addons/ktpamx/configs/plugins.ini`

## Build

```bash
wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPScoreTracker' && bash compile.sh"
```

## Chat Output Examples

**During match (flag capture):**
```
[KTP] Axis captured POINT_ANZIO_PLAZA: kroD- (+2), haha look at this. (+2), CHIRIMBOLOIDE (+2)
[KTP] Allies captured POINT_ANZIO_STREET: soul! CrankinHawg (+2)
```

**End of match:**
```
[KTP] === Capture Summary ===
[KTP] kroD-: 5 caps, 12 pts | soul! CrankinHawg: 4 caps, 10 pts
[KTP] haha look at this.: 3 caps, 8 pts | CHIRIMBOLOIDE: 2 caps, 4 pts
```

With no captures on record the summary collapses to a single line:
```
[KTP] === Capture Summary: No captures recorded ===
```

**Capout recovery:**
```
[KTP] CAPOUT RECOVERY: Allies captured all 5 flags at timelimit — +5 bonus points awarded
```

## Server Log Format

`KTP_CP_CAPTURED` and `ktp_cap_score` are emitted **only while a match is live**.
Warmup captures — including the pre-`.ready` half-2 window, where the matchid is
deliberately still populated — produce chat output but no log entry.

**CP ownership change:**
```
KTP_CP_CAPTURED (cp "3") (name "POINT_ANZIO_PLAZA") (new_owner "2") (old_owner "1") (matchid "1772072225-ATL5")
```

**Per-player score:**
```
"kroD-<17><STEAM_0:1:443810><Axis>" triggered "ktp_cap_score" (cp "3") (cpname "POINT_ANZIO_PLAZA") (points "2") (matchid "1772072225-ATL5")
```

**End-of-match summary:**
```
"kroD-<17><STEAM_0:1:443810><Axis>" triggered "ktp_cap_summary" (captures "5") (cappoints "12") (matchid "1772072225-ATL5")
```

**Capout recovery** (awarded):
```
KTP_CAPOUT_RECOVERY (team "Allies") (bonus "5") (old_score "12") (new_score "17") (cps "5") (matchid "1772072225-ATL5") (elapsed "0.031")
```

**Capout recovery** (write rejected — nothing awarded):
```
KTP_CAPOUT_RECOVERY_FAILED (team "Allies") (bonus "5") (matchid "1772072225-ATL5")
```

These two are the audit trail for any score the plugin changed.

## Related Projects

- [KTPMatchHandler](../KTPMatchHandler) - Match workflow (provides match start/end forwards)
- [KTPAMXX](../KTPAMXX) - Scripting platform with DODX module (provides CP forwards)

## Version

Current: v1.1.4

See [CHANGELOG.md](CHANGELOG.md) for full version history.
