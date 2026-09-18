extends Node
## Drives AnimPreview through a 3D-model hero and a 2D one.
##
##   GODOT --path . res://scenes/anim_preview_smoke.tscn
##   → "ANIM_PREVIEW_SMOKE: ALL PASS"
##
## The preview tool is the thing used to APPROVE a character's animations before
## they ship, so if it silently shows nothing for a 3D unit — every one of its
## controls used to assume an AnimatedSprite2D — the review step is worthless and
## nothing else would catch it. Windowed: the 3D units need a real GPU.

## The 3D side is NOT a fixed hero. It walks every entry in
## VisualUnit.HERO_MODEL_PATHS, so each newly converted character is covered the
## moment it is wired in. It used to check BOUNCER alone, which meant Cross
## (2026-09-09) could be added to the roster and this could still report ALL
## PASS without ever having loaded him — a green gate that verified nothing
## about the thing being shipped.
const HERO_2D := "NEMI"

var _fail: Array[String] = []
var _p: AnimPreview

func _ready() -> void:
	_p = (load("res://scenes/tools/anim_preview.tscn") as PackedScene).instantiate()
	add_child(_p)
	for i in 30:
		await get_tree().process_frame

	# UnitClass is an enum, i.e. a Dictionary at script level, so find_key maps
	# the value back to its name ("CROSS") — already the upper-case form
	# _select() compares against. get_class_name_string() is an INSTANCE method
	# on a spawned unit, so it is no use here, before anything is spawned.
	for uc in VisualUnit.HERO_MODEL_PATHS:
		await _check(str(UnitBase.UnitClass.find_key(uc)), true)
	await _check(HERO_2D, false)

	if _fail.is_empty():
		print("ANIM_PREVIEW_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fail:
			printerr("ANIM_PREVIEW_SMOKE FAIL  " + f)
		get_tree().quit(1)

func _check(hero: String, expect_3d: bool) -> void:
	if not await _select(hero):
		_fail.append("%s: could not select in the unit list" % hero)
		return
	var c: VisualUnit = _p.caster
	if not c:
		_fail.append("%s: nothing spawned" % hero)
		return
	if expect_3d and not c.model3d:
		_fail.append("%s: expected a 3D model, got 2D art" % hero)
		return

	# Every advertised clip must be listed AND playable.
	var listed: Array = _p._anim_names.duplicate()
	if listed.is_empty():
		_fail.append("%s: no animation buttons built" % hero)
		return
	if expect_3d:
		var clips: Array = Array(c.model3d.get_animation_list())
		if listed != clips:
			_fail.append("%s: buttons %s != model clips %s" % [hero, listed, clips])
		for a in clips:
			_p._play_anim(a)
			await get_tree().process_frame
			if _p._current_anim != a:
				_fail.append("%s: clip '%s' did not start" % [hero, a])
		# Pause must actually stop time, and stepping must move it.
		_p._play_anim(clips[0])
		await get_tree().process_frame
		if not _p._paused:
			_p._toggle_pause()
		var t0: float = c.model3d._anim.current_animation_position
		await get_tree().process_frame
		await get_tree().process_frame
		if absf(c.model3d._anim.current_animation_position - t0) > 0.0001:
			_fail.append("%s: paused but the clip kept advancing" % hero)
		_p._step_frame(1)
		if absf(c.model3d._anim.current_animation_position - t0) < 0.0001:
			_fail.append("%s: frame step did nothing" % hero)
		_p._toggle_pause()
	print("  %-10s %-3s  clips: %s" % [hero, "3D" if expect_3d else "2D", ", ".join(listed)])

func _select(hero: String) -> bool:
	var box: OptionButton = _p.unit_box
	for i in box.item_count:
		if box.get_item_text(i).to_upper() == hero:
			box.selected = i
			_p._spawn_selected()
			for j in 20:
				await get_tree().process_frame
			return true
	return false
