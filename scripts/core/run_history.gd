class_name RunHistory
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# Persistent log of finished runs (2026-07-17). main_game.record()s one entry
# at every victory/defeat; the main-menu RUN HISTORY screen reads them back.
# Plain JSON — records are flat dicts, no Godot types to preserve.
# ══════════════════════════════════════════════════════════════════════════════

const PATH := "user://run_history.json"
const MAX_ENTRIES := 100

# entry = {won, wave, kills, damage, crystals, when}
#         + {nodes, spent, difficulties, team}  (2026-08-03, balance baseline)
#
# The four added fields exist because the balance pass fits death wave against
# META INVESTMENT (see BALANCE_PLAN.md §2), and the original five fields make
# run 1 and run 40 indistinguishable in the log. All four are optional with
# empty defaults, so older entries (and any caller that hasn't been updated)
# still parse — the history screen reads only the original keys.
#   nodes        — crystal-tree levels owned when the run STARTED
#   spent        — crystals spent on the tree at that point
#   difficulties — the per-round Easy/Normal/Hard choice, one entry per round
#                  fought. This is a risk-appetite trace, not a mode setting.
#   team         — hero classes fielded at the end
static func record(won: bool, wave: int, kills: int, damage: int, crystals: int,
		nodes: int = -1, spent: int = -1,
		difficulties: Array = [], team: Array = []) -> void:
	var all := entries()
	all.push_front({
		"won": won, "wave": wave, "kills": kills, "damage": damage,
		"crystals": crystals, "when": Time.get_datetime_string_from_system(false, true),
		"nodes": nodes, "spent": spent,
		"difficulties": difficulties, "team": team,
	})
	if all.size() > MAX_ENTRIES:
		all = all.slice(0, MAX_ENTRIES)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))

# ── Export (2026-08-04) ───────────────────────────────────────────────────────
# External testers generate the balance data this project needs, and their runs
# live in user:// — i.e. buried in %APPDATA%\Godot\app_userdata\ on Windows.
# Nobody is walking a tester through that, so the history screen gets a button
# that drops a dated file on their Desktop.
#
# `extra` carries the meta state that isn't per-entry (nodes owned right now,
# wallet) — passed IN rather than read from Progression here so this stays a
# pure static with no autoload dependency (see CONVENTIONS landmine 9).
static func export_json(extra: Dictionary = {}) -> String:
	return JSON.stringify({
		"schema": "rpg-autobattler-runs/1",
		"exported": Time.get_datetime_string_from_system(false, true),
		"meta": extra,
		"stats": stats(),
		"runs": entries(),
	}, "  ")

# Writes the export to the user's Desktop. Returns the absolute path written, or
# "" on failure. Falls back to the user data dir if Desktop can't be resolved
# (some Linux/portable setups return an empty system dir).
static func export_to_desktop(extra: Dictionary = {}) -> String:
	var stamp := Time.get_datetime_string_from_system(false, false) \
			.replace(":", "").replace("-", "").replace("T", "-").replace(" ", "-")
	var fname := "rpg-autobattler-runs-%s.json" % stamp
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	var path := dir.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ""
	f.store_string(export_json(extra))
	f.close()
	return path

static func entries() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if not f:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Array else []

# Aggregates for the header line: {runs, wins, win_rate, best_wave, total_kills}.
static func stats() -> Dictionary:
	var all := entries()
	var wins := 0
	var best := 0
	var kills := 0
	for e in all:
		if bool(e.get("won", false)): wins += 1
		best = maxi(best, int(e.get("wave", 0)))
		kills += int(e.get("kills", 0))
	var runs := all.size()
	return {
		"runs": runs, "wins": wins,
		"win_rate": (float(wins) / float(runs)) if runs > 0 else 0.0,
		"best_wave": best, "total_kills": kills,
	}
