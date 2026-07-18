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
static func record(won: bool, wave: int, kills: int, damage: int, crystals: int) -> void:
	var all := entries()
	all.push_front({
		"won": won, "wave": wave, "kills": kills, "damage": damage,
		"crystals": crystals, "when": Time.get_datetime_string_from_system(false, true),
	})
	if all.size() > MAX_ENTRIES:
		all = all.slice(0, MAX_ENTRIES)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))

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
