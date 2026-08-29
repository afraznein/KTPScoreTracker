# KTPScoreTracker - Claude Code Context

**REQUIRED: Before writing or modifying any code in this repo, invoke the `plugin-dev` skill** (`.claude/skills/plugin-dev/SKILL.md`). It carries the matchid/log-attribution rules and deploy workflow; do not edit the .sma without it loaded.

## Compile Command
To compile this plugin, use:
```bash
wsl bash -c "cd '/mnt/n/Nein_/KTP Git Projects/KTPScoreTracker' && bash compile.sh"
```

This will:
1. Compile `KTPScoreTracker.sma` using KTPAMXX compiler
2. Output to `compiled/KTPScoreTracker.amxx`
3. Auto-stage to `N:\Nein_\KTP Git Projects\KTP DoD Server\serverfiles\dod\addons\ktpamx\plugins\`

## Project Structure
- `KTPScoreTracker.sma` - Main plugin source
- `compile.sh` - WSL compile script (also generates `build_info.inc` with git SHA + UTC build time)
- `compiled/` - Compiled .amxx output
- `CHANGELOG.md` - Version history
- `README.md` - Documentation
- `.github/workflows/smoke.yml` - Tier 1 build-time smoke (calls KTPInfrastructure's reusable workflow)

## Purpose
Verbose capture-scoring plugin for KTP Day of Defeat servers. Outputs real-time capture notifications to chat (who captured, how many points, batched multi-player) and logs detailed HLStatsX-compatible entries to the server log. Tracks per-player capture stats across each match and prints an end-of-match summary.

## Dependencies
- **DODX module with CP tracking** — `controlpoints_init`, `dod_control_point_captured`, `dod_score_event` forwards
- **KTPMatchHandler v0.10.39+** — `ktp_match_start` / `ktp_match_end` forwards drive the per-match stat reset + summary. 0.10.39 is the floor: it added the 4th `half` param and made the start forward fire on every half.
- **`ktp_version_reporter` shared include** (KTPAMXX) — registers with fleet-wide `amx_ktp_versions` rcon command

## Server Deployment
Deploy compiled plugin to production servers using Python/Paramiko (preferred over shell SSH).

**Remote Path:** `~/dod-{port}/serverfiles/dod/addons/ktpamx/plugins/KTPScoreTracker.amxx`

See `N:\Nein_\KTP Git Projects\CLAUDE.md` for full paramiko SSH documentation, server credentials, and working deployment scripts. Stage the new artifact as `KTPScoreTracker.amxx.new`; it swaps in at the 03:00 ET nightly restart, which is the only activation path — extension mode never reloads plugins on a map change (see project-root CLAUDE.md "Scheduled restarts" and this repo's plugin-dev skill).

## Related Projects
- `N:\Nein_\KTP Git Projects\KTPMatchHandler` - Source of `ktp_match_start` / `ktp_match_end` forwards
- `N:\Nein_\KTP Git Projects\KTPAMXX` - Custom AMX Mod X fork (compiler + DODX + shared include)
- `N:\Nein_\KTP Git Projects\KTP DoD Server` - Test server with staged plugins
- `N:\Nein_\KTP Git Projects\TODO.md` - Development TODO list

## Key Files to Update on Version Bump
1. `KTPScoreTracker.sma` - THREE sites: the file header (line 1), `VERSION:`
   (line 5), and `#define PLUGIN_VERSION`. Add the in-file changelog entry too.
2. `CHANGELOG.md` - Add new version section
3. `README.md` - TWO sites: the title header (line 1) and `Current: vX.Y.Z`
   further down. Grep the old version to catch both:
   `grep -n '1\.1\.5' README.md KTPScoreTracker.sma`
4. `N:\Nein_\KTP Git Projects\TODO.md` - Update completed/pending items
