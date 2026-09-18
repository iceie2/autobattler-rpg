extends Node
## Recruits EVERY hero into the real main_game scene, the way buying one does.
##
##   GODOT --headless --path . --fixed-fps 30 res://scenes/recruit_smoke.tscn
##   → "RECRUIT_SMOKE: ALL PASS"
##
## Buying a hero is the one path that puts an arbitrary class into the tree, so
## it's the path where a missing sprite sheet turns into a crash. That's exactly
## what happened on 2026-09-04: five heroes with no walk_south sheet (bouncer,
## cross, pastor, rush, static) died on `null.get_height()` the moment they were
## recruited, and nothing in the existing smokes covered it — the boot smoke only
## ever spawns the default roster.
##
## Each hero must end up with a real visual (3D model, animated sprite, or static
## sprite) and produce no script errors.

var mg = null
var _failures: Array[String] = []

func _ready() -> void:
	mg = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	mg.max_player_units = 40
	var keys: PackedStringArray = UnitBase.UnitClass.keys()

	for cls in UnitBase.UnitClass.values():
		# Only the playable roster is buyable; monsters/summons come from waves.
		if not (VisualUnit.HERO_MODEL_PATHS.has(cls) or VisualUnit.HERO_SPRITE_PATHS.has(cls)):
			continue
		var name := keys[cls]
		if not mg._recruit_hero(cls, UnitBase.Element.NORMAL,
				UnitFactory.generate_recruit_rolls()):
			_failures.append("%s: _recruit_hero refused (no room?)" % name)
			continue
		await get_tree().process_frame

		var u: VisualUnit = null
		for p in mg.player_units:
			if is_instance_valid(p) and p.unit_class == cls:
				u = p
		if not u:
			_failures.append("%s: recruited but not in player_units" % name)
			continue
		if not (u.model3d or u.animated_sprite or u.plain_sprite):
			_failures.append("%s: recruited with NO visual" % name)
			continue
		var kind := "3d" if u.model3d else ("animated" if u.animated_sprite else "static")
		print("  recruited %-12s %s" % [name, kind])

	for i in range(20):
		await get_tree().process_frame

	if _failures.is_empty():
		print("RECRUIT_SMOKE: ALL PASS (%d heroes)" % mg.player_units.size())
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("RECRUIT_SMOKE FAIL  " + f)
		print("RECRUIT_SMOKE: %d FAILURES" % _failures.size())
		get_tree().quit(1)
