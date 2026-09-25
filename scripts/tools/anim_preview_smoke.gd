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

## Smallest bone travel (world units, over one clip) that counts as "this clip
## actually animates". A real clip moves a limb by a sizeable fraction of a
## 1.7-unit character; a dead one is bit-identical frame to frame, so anything
## above float noise separates them. Deliberately tiny — the point is to catch
## ZERO, not to grade the motion.
const BONE_MOVE_MIN := 0.004

## Clips that are SUPPOSED to be a single frozen pose, "HERO:clip".
##
## Each entry needs a reason, and the reason must be that the clip is static BY
## DESIGN — never "this one is broken and I want the gate green". A motion gate
## that reports known-good clips as failures gets ignored within a week, at which
## point it protects nothing.
const STATIC_BY_DESIGN := {
	# BLOODHOUND:idle is a real breathing loop since v003 and is checked like any
	# other clip. The frozen pose it replaced is kept in the file under this name
	# for side-by-side comparison only (never played by the game), and a frozen
	# pose does not move.
	"BLOODHOUND:idle_frozen_v002": true,
	# No idle in Meshy's export; one was synthesized by freezing his aim pose
	# (tools/model3d/freeze_pose.py). A frozen pose does not move.
	"HEADHUNTER:idle": true,
	# An unmapped 1-frame placeholder Meshy ships in the rig bundle. It is not a
	# game clip; NAME_MAP never claims it.
	"DOC:Armature|clip0|baselayer": true,
	# Static's flexible live-wire prop is posed against this deliberate rest
	# reference (VisualUnit sets weapon_variants rest_reference for him).
	"STATIC:rest_reference": true,
}

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
			elif not STATIC_BY_DESIGN.has("%s:%s" % [hero, a]):
				var moved: float = await _bone_travel(c, a)
				if moved < BONE_MOVE_MIN:
					_fail.append("%s: clip '%s' STARTED BUT THE SKELETON DID NOT MOVE"
						% [hero, a] + " (max bone travel %.5f < %.5f)" % [moved, BONE_MOVE_MIN])
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

## Does this clip actually MOVE THE SKELETON, driven through the game's own
## play() path?
##
## WHY THIS EXISTS. Everything above proves a clip is listed, starts, and that
## pause stops it — and every one of those passes on a clip whose channels are
## all constant. That is not hypothetical: a Blender export taken while the
## armature sat in REST mode shipped twice (Rift, then Riot 2026-09-18), giving
## 78 animation channels of which zero moved, and the character stood in his
## A-pose sliding around the board. The prop rubric already makes this point
## about geometry — "they are wiring tests" — and animation had the same hole.
##
## Samples every bone's pose across the clip and returns the largest distance
## any single bone travelled from its first-frame position.
func _bone_travel(c: VisualUnit, clip: String, samples: int = 8) -> float:
	var skel: Skeleton3D = null
	for n in _walk(c.model3d):
		if n is Skeleton3D:
			skel = n
			break
	if skel == null or skel.get_bone_count() == 0:
		return 0.0
	var anim: AnimationPlayer = c.model3d._anim
	var length: float = c.model3d.animation_length(clip)
	if length <= 0.0:
		return 0.0
	var first: Array[Vector3] = []
	var worst := 0.0
	for s in samples:
		anim.seek(length * float(s) / float(samples - 1) * 0.999, true)
		anim.advance(0.0)
		await RenderingServer.frame_post_draw
		for b in skel.get_bone_count():
			var p: Vector3 = skel.get_bone_global_pose(b).origin
			if s == 0:
				first.append(p)
			else:
				worst = maxf(worst, first[b].distance_to(p))
	return worst

static func _walk(n: Node) -> Array:
	var out: Array = [n]
	for ch in n.get_children():
		out.append_array(_walk(ch))
	return out
