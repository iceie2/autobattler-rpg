extends SceneTree

const TEST_PATH := "user://telemetry_v2_smoke.jsonl"

func _initialize() -> void:
	RunTelemetry.clear(TEST_PATH)
	var run_id := RunTelemetry.new_run_id()
	var seq := RunTelemetry.append(run_id, 0, "run_started",
			{"round": 0}, {"meta": {"upgrade_levels": {}}}, TEST_PATH)
	seq = RunTelemetry.append(run_id, seq, "map_node_chosen",
			{"round": 0}, {"chosen": {"id": "test"}}, TEST_PATH)
	seq = RunTelemetry.append(run_id, seq, "battle_ended", {"round": 1},
			{"difficulty": 2, "won": false,
			"duration_sim_s": 12.5}, TEST_PATH)
	seq = RunTelemetry.append(run_id, seq, "run_ended", {"round": 1},
			{"won": false, "wave": 1}, TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_line("{malformed recovery fixture")
	file.close()
	var events := RunTelemetry.read_events(TEST_PATH)
	var report := RunTelemetryReport.build(events)
	var overview: Dictionary = report.get("overview", {})
	var markdown := RunTelemetryReport.to_markdown(report)
	var ok: bool = seq == 4 and events.size() == 4 \
			and events[0].get("schema") == RunTelemetry.SCHEMA \
			and events[0].get("run_id") == run_id \
			and int(events[1].get("seq", 0)) == 2 \
			and events[1].get("type") == "map_node_chosen" \
			and RunTelemetry.last_seq(run_id, TEST_PATH) == 4 \
			and int(overview.get("complete_runs", 0)) == 1 \
			and int(overview.get("battles", 0)) == 1 \
			and report.get("investment_bands", []).size() == 1 \
			and markdown.contains("Brutal")
	RunTelemetry.clear(TEST_PATH)
	if ok:
		print("TELEMETRY_SMOKE_PASS")
		quit(0)
	else:
		push_error("Telemetry JSONL round-trip or malformed-line recovery failed: %s" % str(events))
		quit(1)
