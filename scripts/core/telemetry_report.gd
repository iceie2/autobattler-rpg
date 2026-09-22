class_name RunTelemetryReport
extends RefCounted
# Turns the append-only event stream into human-readable balance evidence.
# All cohorts retain their exact upgrade signature; investment bands are a
# second, explicitly coarse view and never replace the underlying loadout.

const SCHEMA := "rpg-autobattler-telemetry-report/1"
const DIFFICULTY_NAMES := ["Normal", "Veteran", "Brutal"]
const NODE_TYPE_NAMES := ["Relic", "Battle", "Elite", "Boss", "Event", "Merchant", "Camp"]
const HERO_NAMES := [
	"Warrior", "Ranger", "Monk", "Thief", "Black Mage", "White Mage", "Red Mage",
	"Bloodhound", "Bouncer", "Headhunter", "Shauna", "Nemi", "Sheildor", "Lordee",
	"Necro", "Doc", "Riot", "Pastor", "Sable", "Rush", "Stitch", "Coal", "June",
	"Cross", "Sear", "Ember", "Rift", "Zolt", "Lumen", "Static", "Reed", "Vail",
	"Spore", "Zombie", "Bat", "Ant", "Stat Stealer", "Ant Hill", "Hydra",
]

static func build(events: Array) -> Dictionary:
	var runs: Dictionary = {}
	for event in events:
		if not event is Dictionary:
			continue
		var run_id := String(event.get("run_id", ""))
		if run_id == "":
			continue
		if not runs.has(run_id):
			runs[run_id] = {
				"run_id": run_id, "started": false, "complete": false,
				"won": false, "terminal_wave": 0, "meta": {},
				"battles": 0, "battle_wins": 0, "events": [],
			}
		var run: Dictionary = runs[run_id]
		run["events"].append(event)
		run["terminal_wave"] = maxi(int(run["terminal_wave"]),
				int(Dictionary(event.get("context", {})).get("round", 0)))
		var type := String(event.get("type", ""))
		var payload: Dictionary = event.get("payload", {})
		match type:
			"run_started":
				run["started"] = true
				run["meta"] = Dictionary(payload.get("meta", {})).duplicate(true)
			"battle_ended":
				run["battles"] = int(run["battles"]) + 1
				if bool(payload.get("won", false)):
					run["battle_wins"] = int(run["battle_wins"]) + 1
			"run_ended":
				run["complete"] = true
				run["won"] = bool(payload.get("won", false))
				run["terminal_wave"] = int(payload.get("wave", run["terminal_wave"]))
				if Dictionary(run["meta"]).is_empty():
					run["meta"] = Dictionary(payload.get("meta_start", {})).duplicate(true)

	var overview := {"runs": runs.size(), "complete_runs": 0, "incomplete_runs": 0,
		"wins": 0, "battles": 0, "battle_wins": 0, "average_terminal_wave": 0.0}
	var terminal_wave_sum := 0.0
	var bands: Dictionary = {}
	var loadouts: Dictionary = {}
	var difficulties: Dictionary = {}
	var route_choices: Dictionary = {}
	var hero_choices: Dictionary = {}
	var event_choices: Dictionary = {}

	for run_id in runs:
		var run: Dictionary = runs[run_id]
		if bool(run["complete"]):
			overview["complete_runs"] = int(overview["complete_runs"]) + 1
			terminal_wave_sum += int(run["terminal_wave"])
			if bool(run["won"]):
				overview["wins"] = int(overview["wins"]) + 1
		else:
			overview["incomplete_runs"] = int(overview["incomplete_runs"]) + 1
		overview["battles"] = int(overview["battles"]) + int(run["battles"])
		overview["battle_wins"] = int(overview["battle_wins"]) + int(run["battle_wins"])

		var meta: Dictionary = run["meta"]
		var levels: Dictionary = meta.get("upgrade_levels", {})
		var nodes := int(meta.get("nodes_owned", _level_total(levels)))
		_add_run_group(bands, _investment_band(nodes), run, nodes, "")
		var signature := _loadout_signature(levels)
		_add_run_group(loadouts, signature, run, nodes, _loadout_label(levels))

		for event in run["events"]:
			var type := String(event.get("type", ""))
			var payload: Dictionary = event.get("payload", {})
			match type:
				"battle_ended":
					var diff_name := _difficulty_name(int(payload.get("difficulty", -1)))
					_add_outcome(difficulties, diff_name, bool(payload.get("won", false)),
							float(payload.get("duration_sim_s", 0.0)))
				"map_node_chosen":
					var chosen: Dictionary = payload.get("chosen", {})
					var node_type := int(chosen.get("type", -1))
					var route_key := _node_type_name(node_type)
					if int(chosen.get("difficulty", -1)) >= 0 and node_type in [1, 2, 3]:
						route_key += " / " + _difficulty_name(int(chosen["difficulty"]))
					_increment(route_choices, route_key)
				"hero_chosen":
					var chosen: Dictionary = payload.get("chosen", {})
					_increment(hero_choices, _hero_name(int(chosen.get("class", -1))))
				"event_choice_made":
					var event_key := "%s / %s" % [String(payload.get("event_title", "?")),
							String(payload.get("choice_text", "?"))]
					_increment(event_choices, event_key)

	if int(overview["complete_runs"]) > 0:
		overview["average_terminal_wave"] = terminal_wave_sum / float(overview["complete_runs"])
	overview["run_win_rate"] = _rate(int(overview["wins"]), int(overview["complete_runs"]))
	overview["battle_win_rate"] = _rate(int(overview["battle_wins"]), int(overview["battles"]))

	return {
		"schema": SCHEMA,
		"generated_utc": Time.get_datetime_string_from_system(true, true),
		"overview": overview,
		"investment_bands": _finalize_groups(bands),
		"exact_loadouts": _finalize_groups(loadouts),
		"difficulty": _finalize_outcomes(difficulties),
		"route_choices": _count_rows(route_choices),
		"hero_choices": _count_rows(hero_choices),
		"event_choices": _count_rows(event_choices),
	}

static func to_markdown(report: Dictionary) -> String:
	var overview: Dictionary = report.get("overview", {})
	var out := "# RPG Autobattler Telemetry Report\n\n"
	out += "Generated %s. Cohorts are observational; no causal claim is implied.\n\n" \
			% String(report.get("generated_utc", ""))
	out += "## Overview\n\n"
	out += "- Runs: %d complete, %d incomplete\n" % [int(overview.get("complete_runs", 0)),
			int(overview.get("incomplete_runs", 0))]
	out += "- Run win rate: %.1f%%\n" % (100.0 * float(overview.get("run_win_rate", 0.0)))
	out += "- Average terminal wave: %.2f\n" % float(overview.get("average_terminal_wave", 0.0))
	out += "- Battles: %d, %.1f%% won\n\n" % [int(overview.get("battles", 0)),
			100.0 * float(overview.get("battle_win_rate", 0.0))]
	out += _group_table("Investment cohorts", report.get("investment_bands", []))
	out += _group_table("Exact crystal-tree loadouts", report.get("exact_loadouts", []))
	out += _outcome_table("Difficulty results", report.get("difficulty", []))
	out += _count_table("Route choices", report.get("route_choices", []))
	out += _count_table("Hero choices", report.get("hero_choices", []))
	out += _count_table("Event choices", report.get("event_choices", []))
	return out

static func export_to_desktop(events: Array) -> Dictionary:
	if events.is_empty():
		return {}
	var report := build(events)
	var stamp := Time.get_datetime_string_from_system(false, false) \
			.replace(":", "").replace("-", "").replace("T", "-").replace(" ", "-")
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	var json_path := dir.path_join("rpg-autobattler-report-%s.json" % stamp)
	var markdown_path := dir.path_join("rpg-autobattler-report-%s.md" % stamp)
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	var markdown_file := FileAccess.open(markdown_path, FileAccess.WRITE)
	if not json_file or not markdown_file:
		return {}
	json_file.store_string(JSON.stringify(report, "  "))
	markdown_file.store_string(to_markdown(report))
	json_file.close()
	markdown_file.close()
	return {"json": json_path, "markdown": markdown_path}

static func _add_run_group(groups: Dictionary, key: String, run: Dictionary,
		nodes: int, label: String) -> void:
	if not groups.has(key):
		groups[key] = {"key": key, "label": label, "runs": 0, "complete_runs": 0,
			"wins": 0, "terminal_wave_sum": 0.0, "battles": 0,
			"battle_wins": 0, "nodes_min": nodes, "nodes_max": nodes}
	var row: Dictionary = groups[key]
	row["runs"] = int(row["runs"]) + 1
	row["battles"] = int(row["battles"]) + int(run["battles"])
	row["battle_wins"] = int(row["battle_wins"]) + int(run["battle_wins"])
	row["nodes_min"] = mini(int(row["nodes_min"]), nodes)
	row["nodes_max"] = maxi(int(row["nodes_max"]), nodes)
	if bool(run["complete"]):
		row["complete_runs"] = int(row["complete_runs"]) + 1
		row["terminal_wave_sum"] = float(row["terminal_wave_sum"]) + int(run["terminal_wave"])
		if bool(run["won"]):
			row["wins"] = int(row["wins"]) + 1

static func _finalize_groups(groups: Dictionary) -> Array:
	var out: Array = []
	for key in groups:
		var source: Dictionary = groups[key]
		var complete := int(source["complete_runs"])
		var battles := int(source["battles"])
		out.append({
			"key": source["key"], "label": source["label"], "runs": source["runs"],
			"complete_runs": complete, "wins": source["wins"],
			"run_win_rate": _rate(int(source["wins"]), complete),
			"average_terminal_wave": float(source["terminal_wave_sum"]) / float(complete) if complete > 0 else 0.0,
			"battles": battles, "battle_win_rate": _rate(int(source["battle_wins"]), battles),
			"nodes_min": source["nodes_min"], "nodes_max": source["nodes_max"],
		})
	out.sort_custom(func(a, b): return int(a["nodes_min"]) < int(b["nodes_min"]))
	return out

static func _add_outcome(groups: Dictionary, key: String, won: bool, duration: float) -> void:
	if not groups.has(key):
		groups[key] = {"key": key, "battles": 0, "wins": 0, "duration_sum": 0.0}
	var row: Dictionary = groups[key]
	row["battles"] = int(row["battles"]) + 1
	row["duration_sum"] = float(row["duration_sum"]) + duration
	if won:
		row["wins"] = int(row["wins"]) + 1

static func _finalize_outcomes(groups: Dictionary) -> Array:
	var out: Array = []
	for key in groups:
		var source: Dictionary = groups[key]
		var battles := int(source["battles"])
		out.append({"key": key, "battles": battles, "wins": source["wins"],
			"win_rate": _rate(int(source["wins"]), battles),
			"average_duration_sim_s": float(source["duration_sum"]) / float(battles) if battles > 0 else 0.0})
	out.sort_custom(func(a, b): return String(a["key"]) < String(b["key"]))
	return out

static func _increment(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1

static func _count_rows(counts: Dictionary) -> Array:
	var out: Array = []
	for key in counts:
		out.append({"key": key, "count": counts[key]})
	out.sort_custom(func(a, b):
		return int(a["count"]) > int(b["count"]) if a["count"] != b["count"] \
				else String(a["key"]) < String(b["key"]))
	return out

static func _level_total(levels: Dictionary) -> int:
	var total := 0
	for key in levels:
		total += int(levels[key])
	return total

static func _loadout_signature(levels: Dictionary) -> String:
	var keys: Array = levels.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var level := int(levels[key])
		if level > 0:
			parts.append("%s=%d" % [String(key), level])
	return "fresh" if parts.is_empty() else "|".join(parts)

static func _loadout_label(levels: Dictionary) -> String:
	var active := 0
	for key in levels:
		if int(levels[key]) > 0:
			active += 1
	return "Fresh account" if active == 0 else "%d upgraded keys" % active

static func _investment_band(nodes: int) -> String:
	if nodes <= 0: return "Fresh (0 nodes)"
	if nodes <= 9: return "Opening (1–9 nodes)"
	if nodes <= 24: return "Developing (10–24 nodes)"
	if nodes <= 49: return "Established (25–49 nodes)"
	return "High investment (50+ nodes)"

static func _difficulty_name(value: int) -> String:
	return DIFFICULTY_NAMES[value] if value >= 0 and value < DIFFICULTY_NAMES.size() else "Unknown"

static func _hero_name(value: int) -> String:
	return HERO_NAMES[value] if value >= 0 and value < HERO_NAMES.size() else "Unknown"

static func _node_type_name(value: int) -> String:
	return NODE_TYPE_NAMES[value] if value >= 0 and value < NODE_TYPE_NAMES.size() else "Unknown"

static func _rate(numerator: int, denominator: int) -> float:
	return float(numerator) / float(denominator) if denominator > 0 else 0.0

static func _group_table(title: String, rows: Array) -> String:
	var out := "## %s\n\n| Cohort | Runs | Win rate | Avg wave | Battle win |\n|---|---:|---:|---:|---:|\n" % title
	for row in rows:
		var name := String(row.get("key", "")).replace("|", ", ")
		out += "| %s | %d | %.1f%% | %.2f | %.1f%% |\n" % [name,
				int(row.get("complete_runs", 0)), 100.0 * float(row.get("run_win_rate", 0.0)),
				float(row.get("average_terminal_wave", 0.0)),
				100.0 * float(row.get("battle_win_rate", 0.0))]
	return out + "\n"

static func _outcome_table(title: String, rows: Array) -> String:
	var out := "## %s\n\n| Difficulty | Battles | Wins | Win rate | Avg seconds |\n|---|---:|---:|---:|---:|\n" % title
	for row in rows:
		out += "| %s | %d | %d | %.1f%% | %.2f |\n" % [String(row.get("key", "")),
				int(row.get("battles", 0)), int(row.get("wins", 0)),
				100.0 * float(row.get("win_rate", 0.0)),
				float(row.get("average_duration_sim_s", 0.0))]
	return out + "\n"

static func _count_table(title: String, rows: Array) -> String:
	var out := "## %s\n\n| Choice | Count |\n|---|---:|\n" % title
	for row in rows:
		out += "| %s | %d |\n" % [String(row.get("key", "")).replace("|", "/"),
				int(row.get("count", 0))]
	return out + "\n"
