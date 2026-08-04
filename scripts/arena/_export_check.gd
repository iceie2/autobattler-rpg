extends SceneTree
# Throwaway verification for RunHistory.export_to_desktop (2026-08-04).
# RunHistory is a pure static with no autoload dependency, so a bare SceneTree
# script can drive it (CONVENTIONS landmine 9 only bites on autoload users).

func _initialize() -> void:
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
	print("EXPORT_CHECK: PASS — wrote %s (%d bytes, %d runs)" % [
		path.get_file(), txt.length(), (d["runs"] as Array).size()])
	# Clean up so the check doesn't litter the Desktop.
	DirAccess.remove_absolute(path)
	quit(0)
