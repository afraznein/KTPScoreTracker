# KTP Score Tracker v1.0.0

Verbose capture scoring plugin for KTP Day of Defeat servers. Outputs real-time capture notifications to chat and logs detailed HLStatsX-compatible entries to the server log.

## Features

- Real-time chat notifications when flags are captured (who captured, how many points)
- Batched multi-player capture display (all cappers shown in one line)
- Per-player capture stats tracked across the match
- End-of-match capture summary printed to chat
- HLStatsX-compatible server log entries for future stats integration

## Requirements

- **DODX module with CP tracking** (controlpoints_init, dod_control_point_captured, dod_score_event forwards)
- **KTPMatchHandler v0.10.1+** (for ktp_match_start/ktp_match_end forwards)

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

## Server Log Format

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

## Related Projects

- [KTPMatchHandler](../KTPMatchHandler) - Match workflow (provides match start/end forwards)
- [KTPAMXX](../KTPAMXX) - Scripting platform with DODX module (provides CP forwards)

## Version

Current: v1.0.0

See [CHANGELOG.md](CHANGELOG.md) for full version history.
