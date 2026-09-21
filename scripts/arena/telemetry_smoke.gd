extends SceneTree

const TEST_PATH := "user://telemetry_v2_smoke.jsonl"

func _initialize() -> void:
	RunTelemetry.clear(TEST_PATH)
	var run_id := RunTelemetry.new_run_id()
	var seq := RunTelemetry.append(run_id, 0, "run_started",
			{"round": 0}, {"meta": {"upgrade_levels": {}}}, TEST_PATH)
	seq = RunTelemetry.append(run_id, seq, "map_node_chosen",
			{"round": 0}, {"chosen": {"id": "test"}}, TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_line("{malformed recovery fixture")
	file.close()
	var events := RunTelemetry.read_events(TEST_PATH)
	var ok: bool = seq == 2 and events.size() == 2 \
			and events[0].get("schema") == RunTelemetry.SCHEMA \
			and events[0].get("run_id") == run_id \
			and int(events[1].get("seq", 0)) == 2 \
			and events[1].get("type") == "map_node_chosen" \
			and RunTelemetry.last_seq(run_id, TEST_PATH) == 2
	RunTelemetry.clear(TEST_PATH)
	if ok:
		print("TELEMETRY_SMOKE_PASS")
		quit(0)
	else:
		push_error("Telemetry JSONL round-trip or malformed-line recovery failed: %s" % str(events))
		quit(1)
