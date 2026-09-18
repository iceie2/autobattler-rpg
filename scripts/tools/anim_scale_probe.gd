extends Node

# Guards the per-animation size correction (_anim_scale_mult).
# A unit whose clips are all drawn at the same height must render at ONE size —
# the Hill Giant visibly grew ~1.67x mid-attack and snapped back (2026-09-17).
# Units whose clips really are drawn smaller must KEEP their correction.
#
# Run: godot --headless --fixed-fps 30 res://scenes/tools/anim_scale_probe.tscn

var _fail: Array = []

func _report(u: VisualUnit, label: String) -> Dictionary:
	var m: Dictionary = u._anim_scale_mult
	var lo := 99.0
	var hi := 0.0
	for k in m.keys():
		lo = minf(lo, float(m[k])); hi = maxf(hi, float(m[k]))
	print("  %-14s clips=%d  mult range %.3f..%.3f" % [label, m.size(), lo, hi])
	for k in m.keys():
		print("      %-14s %.3f" % [k, float(m[k])])
	return {"lo": lo, "hi": hi, "m": m}

func _ready() -> void:
	print("ANIM SCALE CORRECTION")

	# ── Must be FLAT: every Hill Giant clip is drawn at the same height ───────
	var giant := EnemyFactory.create_hill_giant()
	add_child(giant)
	await get_tree().process_frame
	var g := _report(giant, "hill_giant")
	if g["m"].is_empty():
		_fail.append("hill_giant built no _anim_scale_mult — probe cannot see the bug it guards")
	if g["hi"] - g["lo"] > 0.06:
		_fail.append("hill_giant scale varies %.3f..%.3f across clips; it must render at one size"
			% [g["lo"], g["hi"]])
	if absf(float(g["m"].get("attack", 1.0)) - 1.0) > 0.06:
		_fail.append("hill_giant attack mult is %.3f, not ~1.0 — the swing still pops"
			% float(g["m"].get("attack", 1.0)))

	# ── Must be PRESERVED: Shauna's attack pose is genuinely drawn small ──────
	var shauna := UnitFactory.create_unit(UnitBase.UnitClass.SHAUNA)
	add_child(shauna)
	await get_tree().process_frame
	var s := _report(shauna, "shauna")
	if not s["m"].is_empty() and s["hi"] < 1.3:
		_fail.append("shauna's real size correction was lost (max mult %.3f, expected ~1.7)"
			% s["hi"])

	if _fail.is_empty():
		print("ANIM_SCALE_PROBE: ALL PASS")
		get_tree().quit(0)
		return
	for f in _fail: print("FAIL: ", f)
	print("ANIM_SCALE_PROBE: %d FAILURE(S)" % _fail.size())
	get_tree().quit(1)
