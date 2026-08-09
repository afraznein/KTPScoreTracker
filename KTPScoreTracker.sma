/* KTP Score Tracker v1.1.5
 * Verbose capture scoring with chat output and HLStatsX-compatible logging
 *
 * AUTHOR: Nein_
 * VERSION: 1.1.5
 * DATE: 2026-07-18
 *
 * DESCRIPTION:
 * Consumes DODX control point forwards to provide real-time capture
 * notifications in chat and detailed server log entries. Tracks per-player
 * capture stats across a match and outputs a summary at match end.
 *
 * v1.1.0 adds timelimit capout recovery: detects when a team captures all
 * control points in the same engine frame that timelimit fires, which
 * prevents the game DLL from processing the capout bonus. When detected,
 * awards the bonus points via DODX and notifies players.
 *
 * REQUIREMENTS:
 * - DODX module with CP tracking (controlpoints_init, dod_control_point_captured,
 *   dod_score_event forwards)
 * - KTPMatchHandler v0.10.39+ (ktp_match_start/ktp_match_end forwards; 0.10.39
 *   added the 4th `half` param and made the start forward fire on every half)
 *
 * CHANGELOG:
 *   v1.1.5 (2026-08-09):
 *     * CHANGED: team symbols now come from dodconst.inc (ALLIES/AXIS) rather
 *       than local TEAM_ALLIES/TEAM_AXIS defines shadowing them
 *     * CHANGED: the two byte-identical capout-bonus lookups collapse into
 *       get_capout_bonus()
 *     * FIXED: comment claimed dodx_set_team_score aborts on failure; it has
 *       returned 0 since KTPAMXX 2.7.22, so the checked branch is live
 *
 *   v1.1.4 (2026-07-18):
 *     - ST-01: KTP_CP_CAPTURED / ktp_cap_score log lines now gated on
 *       g_matchActive, so h2 warmup caps aren't tagged with the carried-over
 *       live matchid and misattributed by HLStatsX
 *     - ST-02: deferred capture flush snapshots userid at add time and
 *       revalidates the slot before reading its name (slots recycle in the 0.1s)
 *   v1.1.3 (2026-07-08):
 *     - matchId copied on every ktp_match_start (explicit-OT first start is
 *       half=101, so the half==1 gate logged matchid="" for all OT caps);
 *       a changed id resets per-match stats (new-match boundary)
 *     - Per-player cap stats cleared on client_disconnected (subs no longer
 *       inherit a leaver's slot stats)
 *     - g_matchActive + pending batch cleared in plugin_init so half-2
 *       pre-live warmup caps stop counting into match stats
 *
 *   v1.1.2 (2026-07-06):
 *     - Capout recovery hardened for the pre-changelevel window: gamerules
 *       guard before any score read/write; dodx_set_team_score return
 *       checked so a failed write can't broadcast/log a score the server
 *       never held (KTP_CAPOUT_RECOVERY_FAILED on failure)
 *     - dod_score_event guards the player id before logging/batching
 *
 *   v1.1.1 (2026-04-25):
 *     - Adopted ktp_version_reporter shared include (amx_ktp_versions rcon)
 *     - compile.sh build-info generation (git SHA + UTC build time)
 *
 *   v1.1.0 (2026-04-01):
 *     - Timelimit capout recovery: awards stolen capout bonus when a team
 *       captures all CPs in the same frame as timelimit expiry
 *     - Hooks "Final Scores" log event to detect intermission start
 *     - Reads CP_owner for all CPs via DODX at intermission time
 *     - Awards mp_clan_scoring_bonus_allies/axis via dodx_set_team_score +
 *       dodx_broadcast_team_score
 *
 *   v1.0.0 (2026-02-26):
 *     - Initial release
 *     - Real-time capture chat notifications with player + point attribution
 *     - HLStatsX-compatible server log entries (KTP_CP_CAPTURED, ktp_cap_score,
 *       ktp_cap_summary)
 *     - Per-player capture stats with end-of-match summary
 *     - Batched score events for multi-player captures
 */

#include <amxmodx>
#include <amxmisc>
#include <dodx>
#include <ktp_version_reporter>

#define PLUGIN_NAME    "KTP Score Tracker"
#define PLUGIN_VERSION "1.1.5"
#define PLUGIN_AUTHOR  "Nein_"

#define MAX_CPS      12
#define MAX_CAPPERS  13

// Task ID for batch flush
#define TASK_FLUSH_CAPTURE 55700

// ALLIES/AXIS come from dodconst.inc via <dodx>. Local duplicates retired --
// two symbols for one value is how they silently desync.

// Match types (must match KTPMatchHandler enum)
enum MatchType {
	MATCH_TYPE_COMPETITIVE = 0,
	MATCH_TYPE_SCRIM = 1,
	MATCH_TYPE_12MAN = 2,
	MATCH_TYPE_DRAFT = 3,
	MATCH_TYPE_KTP_OT = 4,
	MATCH_TYPE_DRAFT_OT = 5
};

// CP name cache
new g_cpName[MAX_CPS][64];
new g_cpCount;

// Match state
new bool:g_matchActive;
new g_matchId[64];

// Per-player match stats (indexed by player id, 1-32)
new g_playerCapPoints[33];
new g_playerCapCount[33];

// Pending capture batch
new g_pendingCP = -1;
new g_pendingOwner;
new g_pendingPlayers[MAX_CAPPERS];
new g_pendingUserId[MAX_CAPPERS];   // userid snapshot — slots recycle across the 0.1s flush defer
new g_pendingPoints[MAX_CAPPERS];
new g_pendingCount;

// Capout recovery: track the last CP ownership change time
// If all CPs are owned by one team at intermission and the last flip
// was within CAPOUT_RECOVERY_WINDOW seconds, the capout was stolen.
#define CAPOUT_RECOVERY_WINDOW 2.0

new Float:g_lastCPFlipTime;       // game time of most recent CP ownership change
new g_lastCPFlipTeam;             // team that captured the most recent CP
new g_scoreAtLastFlip;            // team score snapshot at moment of last CP flip
new bool:g_capoutRecoveryDone;    // prevent double-award within a half

public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	KTP_RegisterVersion(PLUGIN_NAME, PLUGIN_VERSION);

	// "Final Scores" is logged by the DoD game DLL when intermission starts.
	// This fires at timelimit expiry BEFORE changelevel — the game is frozen
	// but we still have a brief window to read CP state and award points.
	register_logevent("logevent_final_scores", 0, "0=Final Scores");

	// Globals survive map changes in extension mode. Left armed, the h1→h2
	// map change would count half-2 warmup caps into match stats under the
	// live matchid; ktp_match_start re-arms when the half goes live.
	// g_matchId is NOT cleared — it must carry across the mid-match map change.
	g_matchActive = false;
	g_pendingCP = -1;
	g_pendingCount = 0;
}

// ============================================================
// Client Disconnect
// ============================================================

public client_disconnected(id) {
	// Stats are slot-indexed — a sub joining into this slot must not
	// inherit the leaver's captures.
	if (id >= 1 && id <= 32) {
		g_playerCapPoints[id] = 0;
		g_playerCapCount[id] = 0;
	}
}

// ============================================================
// CP Initialization
// ============================================================

public controlpoints_init() {
	g_cpCount = dodx_objectives_get_num();
	if (g_cpCount > MAX_CPS)
		g_cpCount = MAX_CPS;

	for (new i = 0; i < g_cpCount; i++) {
		dodx_objective_get_data(i, CP_name, g_cpName[i], charsmax(g_cpName[]));
	}

	log_amx("[KTPScoreTracker] CP init: %d control points cached", g_cpCount);
}

// ============================================================
// Control Point Captured
// ============================================================

public dod_control_point_captured(cp_index, new_owner, old_owner) {
	// Flush any pending batch from a previous capture (shouldn't happen, safety)
	if (g_pendingCount > 0)
		flush_capture();

	g_pendingCP = cp_index;
	g_pendingOwner = new_owner;
	g_pendingCount = 0;

	// Track for capout recovery — snapshot team score BEFORE the engine
	// processes the capout. If the engine handles the capout normally,
	// the score will jump by the bonus amount before "Final Scores" fires.
	g_lastCPFlipTime = get_gametime();
	g_lastCPFlipTeam = new_owner;
	g_scoreAtLastFlip = dodx_get_team_score(new_owner);

	// Get CP name
	new cpName[64];
	if (cp_index >= 0 && cp_index < g_cpCount)
		copy(cpName, charsmax(cpName), g_cpName[cp_index]);
	else
		formatex(cpName, charsmax(cpName), "CP_%d", cp_index);

	// Log immediately — only under a live match. g_matchId is deliberately kept
	// populated across the h1->h2 map change, so without this gate a warmup cap
	// (pre-.ready h2 window) would be logged under the prior half's live matchid
	// and misattributed by HLStatsX. Mirrors the g_matchActive counter gate below.
	if (g_matchActive)
		log_message("KTP_CP_CAPTURED (cp ^"%d^") (name ^"%s^") (new_owner ^"%d^") (old_owner ^"%d^") (matchid ^"%s^")",
			cp_index, cpName, new_owner, old_owner, g_matchId);
}

// ============================================================
// Player Score Event
// ============================================================

public dod_score_event(id, score_delta, total_score, cp_index) {
	// Ignore non-CP scores (kill points, etc.)
	if (cp_index < 0)
		return;

	// Guard the id like the stats path below already does — the log line
	// and pending batch would otherwise take garbage ids and emit
	// malformed HLStatsX entries.
	if (id < 1 || id > 32)
		return;

	// If this is for a different CP than pending, flush old batch first
	if (g_pendingCP != cp_index && g_pendingCount > 0)
		flush_capture();

	// Add player to batch
	if (g_pendingCount < MAX_CAPPERS) {
		g_pendingPlayers[g_pendingCount] = id;
		g_pendingUserId[g_pendingCount] = get_user_userid(id);  // stable identity for the deferred flush
		g_pendingPoints[g_pendingCount] = score_delta;
		g_pendingCount++;
	}

	// Update match stats (id already validated by the top guard)
	if (g_matchActive) {
		g_playerCapPoints[id] += score_delta;
		g_playerCapCount[id]++;
	}

	// Log individual score
	new name[32], authid[35], teamName[16];
	get_user_name(id, name, charsmax(name));
	get_user_authid(id, authid, charsmax(authid));
	get_user_team(id, teamName, charsmax(teamName));
	new userId = get_user_userid(id);

	new cpName[64];
	if (cp_index >= 0 && cp_index < g_cpCount)
		copy(cpName, charsmax(cpName), g_cpName[cp_index]);
	else
		formatex(cpName, charsmax(cpName), "CP_%d", cp_index);

	// Live-match only — same warmup-misattribution guard as KTP_CP_CAPTURED.
	if (g_matchActive)
		log_message("^"%s<%d><%s><%s>^" triggered ^"ktp_cap_score^" (cp ^"%d^") (cpname ^"%s^") (points ^"%d^") (matchid ^"%s^")",
			name, userId, authid, teamName, cp_index, cpName, score_delta, g_matchId);

	// Schedule batch flush (only on first player in batch)
	if (g_pendingCount == 1) {
		remove_task(TASK_FLUSH_CAPTURE);
		set_task(0.1, "task_flush_capture", TASK_FLUSH_CAPTURE);
	}
}

// ============================================================
// Batch Flush — Outputs capture chat message
// ============================================================

public task_flush_capture() {
	flush_capture();
}

flush_capture() {
	if (g_pendingCount <= 0) return;

	remove_task(TASK_FLUSH_CAPTURE);

	// Build team name
	new teamStr[8];
	if (g_pendingOwner == ALLIES)
		copy(teamStr, charsmax(teamStr), "Allies");
	else if (g_pendingOwner == AXIS)
		copy(teamStr, charsmax(teamStr), "Axis");
	else
		copy(teamStr, charsmax(teamStr), "???");

	// Get CP name
	new cpName[64];
	if (g_pendingCP >= 0 && g_pendingCP < g_cpCount)
		copy(cpName, charsmax(cpName), g_cpName[g_pendingCP]);
	else
		formatex(cpName, charsmax(cpName), "CP_%d", g_pendingCP);

	// Build player list: "Player1 (+2), Player2 (+2)"
	new playerList[512];
	new pos = 0;
	for (new i = 0; i < g_pendingCount; i++) {
		new pName[32];
		// Slots recycle across the 0.1s defer: only trust the live name if the
		// slot is still connected AND still the same player (userid) that scored.
		new slot = g_pendingPlayers[i];
		if (is_user_connected(slot) && get_user_userid(slot) == g_pendingUserId[i])
			get_user_name(slot, pName, charsmax(pName));
		else
			copy(pName, charsmax(pName), "a departed player");

		if (i > 0)
			pos += formatex(playerList[pos], charsmax(playerList) - pos, ", ");

		pos += formatex(playerList[pos], charsmax(playerList) - pos, "%s (+%d)", pName, g_pendingPoints[i]);
	}

	// Chat output
	client_print(0, print_chat, "[KTP] %s captured %s: %s", teamStr, cpName, playerList);

	// Reset pending state
	g_pendingCP = -1;
	g_pendingCount = 0;
}

// ============================================================
// Match Start / End (KTPMatchHandler forwards)
// ============================================================

public ktp_match_start(const matchId[], const map[], MatchType:matchType, half) {
	// Copy on every start — explicit-OT matches fire their first start with
	// half=101, so gating on half==1 left matchid empty (or stale: .forcereset
	// never fires ktp_match_end). A changed id is the new-match boundary, and
	// half==1 also resets: 1.3-Community ids carry no timestamp, so the same
	// queue restarted after a .forcereset presents an IDENTICAL id — without
	// the half==1 reset the aborted attempt's caps would leak into the restart.
	if (!equal(g_matchId, matchId) || half == 1) {
		copy(g_matchId, charsmax(g_matchId), matchId);
		reset_player_stats();
	}
	g_matchActive = true;
	g_capoutRecoveryDone = false;
	g_lastCPFlipTime = 0.0;
	g_lastCPFlipTeam = 0;
	g_scoreAtLastFlip = 0;
}

public ktp_match_end(const matchId[], const map[], MatchType:matchType, team1Score, team2Score) {
	g_matchActive = false;

	// Flush any pending capture batch
	if (g_pendingCount > 0)
		flush_capture();

	// Output end-of-match summary
	output_match_summary();

	// Reset for next match
	g_matchId[0] = 0;
	reset_player_stats();
}

// ============================================================
// End-of-Match Summary
// ============================================================

output_match_summary() {
	// Collect players with captures into a sortable list
	new pIds[32], pPoints[32], pCaps[32];
	new count = 0;

	for (new i = 1; i <= 32; i++) {
		if (g_playerCapCount[i] > 0 && is_user_connected(i)) {
			pIds[count] = i;
			pPoints[count] = g_playerCapPoints[i];
			pCaps[count] = g_playerCapCount[i];
			count++;
		}
	}

	if (count == 0) {
		client_print(0, print_chat, "[KTP] === Capture Summary: No captures recorded ===");
		return;
	}

	// Sort by points descending (simple bubble sort)
	for (new i = 0; i < count - 1; i++) {
		for (new j = i + 1; j < count; j++) {
			if (pPoints[j] > pPoints[i]) {
				// Swap
				new tmp;
				tmp = pIds[i]; pIds[i] = pIds[j]; pIds[j] = tmp;
				tmp = pPoints[i]; pPoints[i] = pPoints[j]; pPoints[j] = tmp;
				tmp = pCaps[i]; pCaps[i] = pCaps[j]; pCaps[j] = tmp;
			}
		}
	}

	// Print header
	client_print(0, print_chat, "[KTP] === Capture Summary ===");

	// Print two players per line
	new line[256];
	for (new i = 0; i < count; i += 2) {
		new name1[32];
		get_user_name(pIds[i], name1, charsmax(name1));

		if (i + 1 < count) {
			new name2[32];
			get_user_name(pIds[i + 1], name2, charsmax(name2));
			formatex(line, charsmax(line), "[KTP] %s: %d caps, %d pts | %s: %d caps, %d pts",
				name1, pCaps[i], pPoints[i],
				name2, pCaps[i + 1], pPoints[i + 1]);
		} else {
			formatex(line, charsmax(line), "[KTP] %s: %d caps, %d pts",
				name1, pCaps[i], pPoints[i]);
		}

		client_print(0, print_chat, "%s", line);
	}

	// Log per-player summary
	for (new i = 0; i < count; i++) {
		new name[32], authid[35], teamName[16];
		get_user_name(pIds[i], name, charsmax(name));
		get_user_authid(pIds[i], authid, charsmax(authid));
		get_user_team(pIds[i], teamName, charsmax(teamName));
		new userId = get_user_userid(pIds[i]);

		log_message("^"%s<%d><%s><%s>^" triggered ^"ktp_cap_summary^" (captures ^"%d^") (cappoints ^"%d^") (matchid ^"%s^")",
			name, userId, authid, teamName, pCaps[i], pPoints[i], g_matchId);
	}
}

// ============================================================
// Timelimit Capout Recovery
// ============================================================

// Fired when DoD logs "Final Scores: Allies: X   Axis: Y" — intermission start.
// At this point g_fGameOver is set in the game DLL, but the engine hasn't
// called changelevel yet. We can still read CP state and modify scores.
public logevent_final_scores() {
	if (!g_matchActive)
		return;

	if (g_capoutRecoveryDone)
		return;

	if (g_cpCount < 1)
		return;

	// This path reads AND writes gamerules scores inside the pre-changelevel
	// window. Without gamerules the write would fail while the read silently
	// falls back to the message-tracked score — bail before deciding anything
	// from mismatched sources.
	if (!dodx_has_gamerules()) {
		log_amx("[KTPScoreTracker] Capout check skipped: gamerules unavailable at intermission");
		return;
	}

	// Only recover if a CP flip happened very recently (same frame / within window)
	new Float:elapsed = get_gametime() - g_lastCPFlipTime;
	if (g_lastCPFlipTime == 0.0 || elapsed > CAPOUT_RECOVERY_WINDOW)
		return;

	// Check if all CPs are owned by the same team
	new capoutTeam = check_all_cps_owned();
	if (capoutTeam == 0)
		return;

	// Safety: the capout team should match the team that just flipped a CP
	if (capoutTeam != g_lastCPFlipTeam)
		return;

	// Check if the engine already awarded the capout bonus.
	// Compare current score against our snapshot from the moment of the CP flip.
	// If the score already increased by >= the bonus amount, the engine handled it.
	new bonus = get_capout_bonus(capoutTeam);

	new currentScore = dodx_get_team_score(capoutTeam);
	new scoreDelta = currentScore - g_scoreAtLastFlip;

	if (bonus > 0 && scoreDelta >= bonus) {
		// Score already jumped by at least the bonus amount since the last flip.
		// The engine handled the capout — individual CP points + capout bonus
		// are both included in this delta. No recovery needed.
		log_amx("[KTPScoreTracker] Capout check: %s owns all %d CPs but score already jumped %d (>= bonus %d) since last flip — engine handled it",
			(capoutTeam == ALLIES) ? "Allies" : "Axis", g_cpCount, scoreDelta, bonus);
		return;
	}

	// All CPs owned by one team + recent flip + intermission just started
	// + score did NOT include the bonus = capout was stolen by timelimit
	award_capout_recovery(capoutTeam);
}

// Capout bonus for a side. Was duplicated verbatim at two call sites, which is how
// a future edit to one cvar name silently desyncs them.
get_capout_bonus(team) {
	if (team == ALLIES)
		return get_cvar_num("mp_clan_scoring_bonus_allies");
	return get_cvar_num("mp_clan_scoring_bonus_axis");
}

// Returns team ID (ALLIES or AXIS) if all CPs are owned by one team,
// or 0 if ownership is mixed/neutral.
check_all_cps_owned() {
	new firstOwner = 0;

	for (new i = 0; i < g_cpCount; i++) {
		new owner = dodx_objective_get_data(i, CP_owner);

		// Neutral or unowned CP — no capout
		if (owner != ALLIES && owner != AXIS)
			return 0;

		if (firstOwner == 0)
			firstOwner = owner;
		else if (owner != firstOwner)
			return 0;  // Mixed ownership
	}

	return firstOwner;
}

award_capout_recovery(team) {
	g_capoutRecoveryDone = true;

	// Read the capout bonus from the map config cvars
	new bonus = get_capout_bonus(team);

	if (bonus <= 0) {
		log_amx("[KTPScoreTracker] Capout recovery: team %d owns all %d CPs but bonus cvar is %d, skipping",
			team, g_cpCount, bonus);
		return;
	}

	// Read current score and add bonus
	new currentScore = dodx_get_team_score(team);
	new newScore = currentScore + bonus;

	// Build team name string
	new teamStr[8];
	if (team == ALLIES)
		copy(teamStr, charsmax(teamStr), "Allies");
	else
		copy(teamStr, charsmax(teamStr), "Axis");

	// Apply — checked: a failed write must not produce the success
	// broadcast/chat/log below. dodx_set_team_score returns 0 on failure
	// (KTPAMXX 2.7.22+, fleet-live since 07-11), so this is the live failure
	// path, not dead code.
	if (!dodx_set_team_score(team, newScore)) {
		log_amx("[KTPScoreTracker] Capout recovery FAILED: dodx_set_team_score(%d, %d) rejected — no points awarded",
			team, newScore);
		log_message("KTP_CAPOUT_RECOVERY_FAILED (team ^"%s^") (bonus ^"%d^") (matchid ^"%s^")",
			teamStr, bonus, g_matchId);
		return;
	}
	dodx_broadcast_team_score(team, newScore);

	// Notify players
	client_print(0, print_chat, "[KTP] CAPOUT RECOVERY: %s captured all %d flags at timelimit — +%d bonus points awarded",
		teamStr, g_cpCount, bonus);

	// Log for HLStatsX / audit
	log_message("KTP_CAPOUT_RECOVERY (team ^"%s^") (bonus ^"%d^") (old_score ^"%d^") (new_score ^"%d^") (cps ^"%d^") (matchid ^"%s^") (elapsed ^"%.3f^")",
		teamStr, bonus, currentScore, newScore, g_cpCount, g_matchId, get_gametime() - g_lastCPFlipTime);

	log_amx("[KTPScoreTracker] Capout recovery awarded: %s +%d (score %d -> %d), %d CPs, elapsed %.3fs since last flip",
		teamStr, bonus, currentScore, newScore, g_cpCount, get_gametime() - g_lastCPFlipTime);
}

// ============================================================
// Helpers
// ============================================================

reset_player_stats() {
	for (new i = 0; i <= 32; i++) {
		g_playerCapPoints[i] = 0;
		g_playerCapCount[i] = 0;
	}
}
