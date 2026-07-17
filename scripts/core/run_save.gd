class_name RunSave
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# Mid-run save (2026-07-17 user request). main_game writes a checkpoint at the
# start of every prep phase (and after recruits/relics/events/quit-to-menu),
# so closing the game or crashing costs at most the current prep's purchases —
# never the run. The file also carries the run's crystals, which previously
# only banked into Progression at victory/defeat.
#
# Serialized with var_to_str/str_to_var (NOT JSON): relic dicts, Vector2i grid
# positions and Colors survive the round-trip natively. str_to_var cannot
# execute code, so loading is safe.
#
# main_game owns the actual capture/apply logic (save_run/_resume_run) — this
# class is just the file IO + the cross-scene "resume, don't start fresh" flag.
# ══════════════════════════════════════════════════════════════════════════════

const PATH := "user://run_save.json"
const VERSION := 1

# Set by the main menu's CONTINUE RUN button; read once by main_game._ready.
static var resume_on_start := false

static func exists() -> bool:
	return FileAccess.file_exists(PATH)

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

static func write_data(data: Dictionary) -> void:
	data["version"] = VERSION
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(var_to_str(data))

static func read_data() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if not f:
		return {}
	var parsed = str_to_var(f.get_as_text())
	if not (parsed is Dictionary) or int(parsed.get("version", -1)) != VERSION:
		return {}
	return parsed
