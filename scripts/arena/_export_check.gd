extends SceneTree
# Throwaway verification for RunHistory.export_to_desktop (2026-08-04).
# RunHistory is a pure static with no autoload dependency, so a bare SceneTree
# script can drive it (CONVENTIONS landmine 9 only bites on autoload users).

func _initialize() -> void:
	# Exercise the 2026-08-05 fields (relics/equipment/fusion_log/death) too —
	# record() must accept them and export_json() must round-trip them. record()
	# writes to the real persistent user://run_history.json, so this test entry
	# is popped back off at the end rather than left polluting real save data.
	RunHistory.record(false, 12, 30, 5000, 40, 5, 100, ["Normal"], ["WARRIOR"], [4],
			["r1", "r2"], {"Rare": 2, "Common": 5},
			[{"cap": 1, "available": ["Lifesteal", "Haste"], "picked": ["Haste"], "was_a_choice": true}],
			{"hero": "Grug", "killed_by": "Orc Warlord", "wave": 12},
			3, 44)
	var path := RunHistory.export_to_desktop({"nodes_owned": 7, "crystals": 123})
	if path == "":
		print("EXPORT_CHECK: FAIL — export_to_desktop returned empty")
		quit(1); return
	if not FileAccess.file_exists(path):
		print("EXPORT_CHECK: FAIL — no file at %s" % path)
		quit(1); return
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("EXPORT_CHECK: FAIL — not valid JSON")
		quit(1); return
	var d := parsed as Dictionary
	for key in ["schema", "exported", "meta", "stats", "runs"]:
		if not d.has(key):
			print("EXPORT_CHECK: FAIL — missing key %s" % key)
			quit(1); return
	if int((d["meta"] as Dictionary).get("nodes_owned", -1)) != 7:
		print("EXPORT_CHECK: FAIL — meta.nodes_owned did not round-trip")
		quit(1); return

	var runs: Array = d["runs"]
	if runs.is_empty():
		print("EXPORT_CHECK: FAIL — no runs recorded")
		quit(1); return
	var latest: Dictionary = runs[0]   # record() push_fronts
	# 2026-08-07 fields. nodes_end/spent_end exist because a mid-session respec
	# zeroes the run-START snapshot and made an invested account look fresh; if
	# they stop round-tripping, the meta-investment axis silently breaks again.
	if int(latest.get("nodes_end", -99)) != 3 or int(latest.get("spent_end", -99)) != 44:
		print("EXPORT_CHECK: FAIL — nodes_end/spent_end did not round-trip")
		quit(1); return
	# `team` must survive a DEFEAT. It used to be built from survivors, so every
	# losing run — the only kind that needs explaining — exported an empty list.
	if (latest.get("team", []) as Array).is_empty():
		print("EXPORT_CHECK: FAIL — team empty on a recorded defeat")
		quit(1); return
	# Difficulties must be readable labels, not raw enum ints (a tester export of
	# 117 zeros was uninterpretable until someone read the source).
	for diff in (latest.get("difficulties", []) as Array):
		if typeof(diff) != TYPE_STRING:
			print("EXPORT_CHECK: FAIL — difficulty %s is not a label" % str(diff))
			quit(1); return
	for key in ["team_levels", "relics", "equipment", "fusion_log", "death"]:
		if not latest.has(key):
			print("EXPORT_CHECK: FAIL — run entry missing key %s" % key)
			quit(1); return
	if latest.get("relics", []) != ["r1", "r2"]:
		print("EXPORT_CHECK: FAIL — relics did not round-trip")
		quit(1); return
	if int((latest.get("equipment", {}) as Dictionary).get("Rare", -1)) != 2:
		print("EXPORT_CHECK: FAIL — equipment summary did not round-trip")
		quit(1); return
	if str((latest.get("death", {}) as Dictionary).get("killed_by", "")) != "Orc Warlord":
		print("EXPORT_CHECK: FAIL — death cause did not round-trip")
		quit(1); return

	print("EXPORT_CHECK: PASS — wrote %s (%d bytes, %d runs)" % [
		path.get_file(), txt.length(), runs.size()])
	# Clean up: the Desktop export file, AND the test entry injected into the
	# real persistent user://run_history.json so this check leaves no trace.
	DirAccess.remove_absolute(path)
	var real := RunHistory.entries()
	if not real.is_empty():
		real.pop_front()
		var f := FileAccess.open(RunHistory.PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(real))
	quit(0)
