class_name RunTelemetry
extends RefCounted
# Local, append-only gameplay telemetry. This never sends data anywhere and
# must never consume gameplay RNG. One JSON object per line keeps completed
# decisions readable even when a run or process ends unexpectedly.

const SCHEMA := "rpg-autobattler-telemetry/2"
const PATH := "user://telemetry_v2.jsonl"
const MAX_BYTES := 10 * 1024 * 1024

static func new_run_id() -> String:
	# System time/process identity is sufficient for a local correlation id and,
	# unlike randi(), cannot perturb a seeded run.
	return "%x-%x-%x" % [int(Time.get_unix_time_from_system()),
			Time.get_ticks_usec(), OS.get_process_id()]

static func append(run_id: String, seq: int, type: String,
		context: Dictionary = {}, payload: Dictionary = {}, path: String = PATH) -> int:
	var next_seq := seq + 1
	if path == PATH and "--no-telemetry" in OS.get_cmdline_user_args():
		return next_seq
	var event := {
		"schema": SCHEMA,
		"event_id": "%s:%d" % [run_id, next_seq],
		"run_id": run_id,
		"seq": next_seq,
		"type": type,
		"occurred_utc": Time.get_datetime_string_from_system(true, true),
		"build": {
			"version": String(ProjectSettings.get_setting("application/config/version", "unknown")),
		},
		"context": context.duplicate(true),
		"payload": payload.duplicate(true),
	}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file:
		file.seek_end()
		file.store_line(JSON.stringify(event))
		file.close()
	return next_seq

static func read_events(path: String = PATH) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return out
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "":
			continue
		var parser := JSON.new()
		if parser.parse(line) != OK:
			continue
		var parsed = parser.data
		if parsed is Dictionary and String(parsed.get("schema", "")) == SCHEMA:
			out.append(parsed)
	file.close()
	return out

static func last_seq(run_id: String, path: String = PATH) -> int:
	var latest := 0
	for event in read_events(path):
		if String(event.get("run_id", "")) == run_id:
			latest = maxi(latest, int(event.get("seq", 0)))
	return latest

static func export_to_desktop() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	var stamp := Time.get_datetime_string_from_system(false, false) \
			.replace(":", "").replace("-", "").replace("T", "-").replace(" ", "-")
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	var destination := dir.path_join("rpg-autobattler-telemetry-%s.jsonl" % stamp)
	return destination if DirAccess.copy_absolute(
			ProjectSettings.globalize_path(PATH), destination) == OK else ""

static func clear(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func file_size(path: String = PATH) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return 0
	var length := file.get_length()
	file.close()
	return length
